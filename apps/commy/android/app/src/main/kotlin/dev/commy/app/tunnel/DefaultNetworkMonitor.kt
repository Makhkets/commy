package dev.commy.app.tunnel

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import java.net.InterfaceAddress
import java.net.NetworkInterface
import java.util.concurrent.CopyOnWriteArrayList
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface

/**
 * Watches the default network and tells the core about it.
 *
 * **This class is acceptance criterion 2 of milestone M1** — "the tunnel
 * survives Wi-Fi ↔ mobile". The way it survives is that nothing is torn down:
 * the TUN device, the sockets and the core all stay exactly where they are, and
 * the only thing that happens is
 *
 *   1. `InterfaceUpdateListener.updateDefaultInterface(...)` — the core learns
 *      which interface to bind new sockets to, and
 *   2. `CommandServer.resetNetwork()` — the core drops the connections that
 *      were pinned to the interface that went away.
 *
 * Rebuilding the tunnel on a network change is the obvious implementation and
 * the wrong one: it breaks every open connection, including the ones that would
 * have survived, and the user sees a dropped call for a handover the phone
 * handled perfectly well.
 *
 * ## The network this class must never report
 *
 * **Our own tunnel.** `registerDefaultNetworkCallback` answers "what is the
 * default network for this app", and the moment a VPN is established that
 * answer becomes the VPN — for the app that built it as much as for anyone
 * else. Reporting it puts the core in a loop it cannot see: sing-box drops its
 * own interface from the candidate list (`MyInterfaces`) and then looks for one
 * matching the index it was handed, finds none, and every dial dies with
 * *no available network interface*. On a device that reads as a tunnel that
 * connects and carries nothing — no error on screen, nothing obviously wrong in
 * the log unless you know that `tun0` has no business being the default.
 *
 * So the watch is not the default-network callback. It is a request for a
 * network that carries `NET_CAPABILITY_NOT_VPN` ([WATCHED]), which is the only
 * way to ask Android this question and be certain of the answer. It also keeps
 * the handover working while the tunnel is up: once the VPN is the default,
 * the default-network callback stops saying anything about Wi-Fi going away,
 * which is exactly the event acceptance criterion 2 is about.
 */
internal class DefaultNetworkMonitor(context: Context) {

    private val connectivity =
        context.applicationContext.getSystemService(ConnectivityManager::class.java)

    private val listeners = CopyOnWriteArrayList<InterfaceUpdateListener>()

    @Volatile
    private var commandServer: CommandServer? = null

    /** The network the core should bind to, for `VpnService.setUnderlyingNetworks`. */
    @Volatile
    var defaultNetwork: Network? = null
        private set

    /**
     * Called whenever [defaultNetwork] changes, on the callback's own thread.
     *
     * The service uses it for `setUnderlyingNetworks`. Kept as a hook rather
     * than a direct call so this class stays testable without a VpnService, and
     * so it owns nothing about the tunnel.
     */
    @Volatile
    var onDefaultNetworkChanged: ((Network?) -> Unit)? = null

    @Volatile
    private var current = ABSENT

    private var callback: ConnectivityManager.NetworkCallback? = null

    /**
     * Networks matching [WATCHED], newest last.
     *
     * Needed only below API 31, where the platform reports every matching
     * network rather than the best one and picking between them is ours to do.
     * Guarded by its own monitor because the callbacks arrive on a platform
     * thread and [close] runs on ours.
     */
    private val available = LinkedHashSet<Network>()

    /** Attached once the core is up, so a change can reach `resetNetwork()`. */
    fun attach(server: CommandServer) {
        commandServer = server
    }

    /**
     * Registers one of libbox's listeners.
     *
     * The current interface is pushed synchronously before returning. Without
     * it the core starts with no default interface and the first dial fails
     * with a routing error that looks like a broken config.
     */
    fun register(listener: InterfaceUpdateListener) {
        listeners.addIfAbsent(listener)
        if (callback == null) {
            startWatching()
        }
        seed()
        current.let { listener.updateDefaultInterface(it.name, it.index, it.expensive, false) }
    }

    /**
     * Fills in the current network without waiting for a callback.
     *
     * The callbacks arrive on a platform thread within milliseconds, and the
     * core's first dial can easily be quicker. Asking the question directly
     * costs one lookup and turns a race into an answer; a callback landing
     * afterwards with the same network publishes nothing, because [publish]
     * compares before it speaks.
     */
    private fun seed() {
        if (current != ABSENT) {
            return
        }
        val manager = connectivity ?: return
        val candidate = usableNetworks(manager).lastOrNull() ?: return
        synchronized(available) {
            available.remove(candidate)
            available.add(candidate)
        }
        refresh(candidate)
    }

    /**
     * Every network that would satisfy [WATCHED], the active one last.
     *
     * Ordered that way so the caller can take the last and get the one the
     * platform would have chosen, with the others as a fallback for the moment
     * right after a handover when `activeNetwork` is briefly nothing.
     */
    @Suppress("DEPRECATION")
    private fun usableNetworks(manager: ConnectivityManager): List<Network> {
        val active = manager.activeNetwork?.takeIf { isUsable(manager, it) }
        val others = runCatching { manager.allNetworks.toList() }.getOrDefault(emptyList())
            .filter { it != active && isUsable(manager, it) }
        return others + listOfNotNull(active)
    }

    private fun isUsable(manager: ConnectivityManager, network: Network): Boolean {
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
    }

    fun unregister(listener: InterfaceUpdateListener) {
        listeners.remove(listener)
        if (listeners.isEmpty()) {
            stopWatching()
        }
    }

    fun close() {
        listeners.clear()
        stopWatching()
        commandServer = null
        onDefaultNetworkChanged = null
        defaultNetwork = null
    }

    private fun startWatching() {
        val manager = connectivity ?: return
        val watcher = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                synchronized(available) {
                    // Re-inserted rather than kept in place: "newest last" is
                    // the whole ordering, and a set does not reorder on add.
                    available.remove(network)
                    available.add(network)
                }
                refresh(network)
            }

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) {
                if (defaultNetwork == network) {
                    refresh(network)
                }
            }

            override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) {
                if (defaultNetwork == network) {
                    refresh(network)
                }
            }

            override fun onLost(network: Network) {
                val next = synchronized(available) {
                    available.remove(network)
                    available.lastOrNull()
                }
                if (defaultNetwork != network) {
                    return
                }
                if (next == null) {
                    setDefaultNetwork(null)
                    publish(ABSENT)
                } else {
                    refresh(next)
                }
            }
        }
        callback = watcher
        runCatching { register(manager, watcher) }
            .onFailure {
                callback = null
                Log.w(TAG, "cannot watch the underlying network: ${it.message}")
            }
    }

    /**
     * Subscribes to [WATCHED].
     *
     * From API 31 the platform will pick the best matching network itself,
     * which is the same answer the default-network callback gives minus the
     * VPN. Below that every match is reported and [available] does the picking.
     */
    private fun register(
        manager: ConnectivityManager,
        watcher: ConnectivityManager.NetworkCallback,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            manager.registerBestMatchingNetworkCallback(
                WATCHED,
                watcher,
                Handler(Looper.getMainLooper()),
            )
        } else {
            manager.registerNetworkCallback(WATCHED, watcher)
        }
    }

    private fun stopWatching() {
        val watcher = callback ?: return
        callback = null
        synchronized(available) { available.clear() }
        runCatching { connectivity?.unregisterNetworkCallback(watcher) }
    }

    private fun refresh(network: Network) {
        val manager = connectivity ?: return
        // The name is read first: a network with no link properties yet is one
        // we cannot describe to the core, and adopting it would only replace a
        // working answer with an empty one.
        val name = manager.getLinkProperties(network)?.interfaceName ?: return
        setDefaultNetwork(network)
        val capabilities = manager.getNetworkCapabilities(network)
        val expensive = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            ?.not() ?: false
        publish(
            DefaultInterface(
                name = name,
                index = indexOf(name),
                expensive = expensive,
            ),
        )
    }

    private fun setDefaultNetwork(next: Network?) {
        if (defaultNetwork == next) {
            return
        }
        defaultNetwork = next
        runCatching { onDefaultNetworkChanged?.invoke(next) }
    }

    private fun publish(next: DefaultInterface) {
        if (next == current) {
            return
        }
        current = next
        for (listener in listeners) {
            // isConstrained is left false: the capability that carries it
            // (NET_CAPABILITY_NOT_BANDWIDTH_CONSTRAINED) only exists on very
            // recent platforms, and guessing it wrong makes the core throttle
            // itself on a perfectly good link.
            runCatching { listener.updateDefaultInterface(next.name, next.index, next.expensive, false) }
        }
        // Order matters: the core has to know the new interface before it is
        // told to drop what was bound to the old one.
        runCatching { commandServer?.resetNetwork() }
    }

    /**
     * Answers `PlatformInterface.getInterfaces()`.
     *
     * The flag bits are Go's `net.Flags`, not Android's — up, broadcast,
     * loopback, point-to-point, multicast, running, in that order from bit 0.
     * Handing over Android's own flag values here produces a core that thinks
     * every interface is down.
     */
    fun interfaces(): List<LibboxNetworkInterface> {
        val manager = connectivity
        val metadata = manager?.let(::collectMetadata).orEmpty()
        val sources = runCatching { NetworkInterface.getNetworkInterfaces()?.toList() }
            .getOrNull()
            .orEmpty()
        // Explicit accessors, not property syntax, and this is not a style
        // choice: gomobile emits getMTU/getDNSServer, and Kotlin maps a getter
        // whose name continues in capitals to a property that keeps them —
        // `MTU`, `DNSServer`. Calling the methods sidesteps the whole question.
        return sources.map { source ->
            val extra = metadata[source.name]
            LibboxNetworkInterface().apply {
                setName(source.name)
                setIndex(source.index)
                runCatching { setMTU(source.mtu) }
                setAddresses(
                    StringArray(
                        source.interfaceAddresses.mapNotNull(::goPrefix),
                    ),
                )
                setFlags(goFlags(source))
                setType(extra?.type ?: Libbox.InterfaceTypeOther)
                setMetered(extra?.metered ?: false)
                setDNSServer(StringArray(extra?.dnsServers.orEmpty()))
            }
        }
    }

    /**
     * One interface address the way Go's `netip.ParsePrefix` will take it.
     *
     * Java prints a link-local IPv6 address with its scope — `fe80::1%wlan0` —
     * and every interface that is up has one. Go refuses a zone inside a
     * prefix, and libbox parses these with `MustParsePrefix`: not an error
     * returned, a panic, in our process. Every connect on a real device died
     * here, on an address the tunnel never uses. The scope is dropped as text
     * rather than by rebuilding the address from its bytes, because
     * `InetAddress.getByAddress` turns an IPv4-mapped address into an
     * `Inet4Address`, and that next to a prefix length of 96 is the same panic
     * by another road.
     */
    private fun goPrefix(entry: InterfaceAddress): String? {
        val host = entry.address?.hostAddress?.substringBefore('%')
        if (host.isNullOrEmpty()) {
            return null
        }
        return "$host/${entry.networkPrefixLength}"
    }

    @Suppress("DEPRECATION")
    private fun collectMetadata(manager: ConnectivityManager): Map<String, InterfaceMetadata> {
        val result = mutableMapOf<String, InterfaceMetadata>()
        for (network in manager.allNetworks) {
            val properties = manager.getLinkProperties(network) ?: continue
            val name = properties.interfaceName ?: continue
            val capabilities = manager.getNetworkCapabilities(network)
            result[name] = InterfaceMetadata(
                type = interfaceType(capabilities),
                metered = capabilities
                    ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)?.not() ?: false,
                dnsServers = properties.dnsServers.mapNotNull { it.hostAddress },
            )
        }
        return result
    }

    private fun interfaceType(capabilities: NetworkCapabilities?): Int = when {
        capabilities == null -> Libbox.InterfaceTypeOther
        // A VPN carries the transport of whatever it rides on, so this test has
        // to come first or our own tunnel is reported as Wi-Fi.
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ->
            Libbox.InterfaceTypeOther
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ->
            Libbox.InterfaceTypeCellular
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ->
            Libbox.InterfaceTypeEthernet
        else -> Libbox.InterfaceTypeOther
    }

    private fun goFlags(source: NetworkInterface): Int {
        var flags = 0
        runCatching {
            if (source.isUp) flags = flags or FLAG_UP or FLAG_RUNNING
            if (source.supportsMulticast()) flags = flags or FLAG_MULTICAST
            if (source.isLoopback) flags = flags or FLAG_LOOPBACK
            if (source.isPointToPoint) flags = flags or FLAG_POINT_TO_POINT
        }
        return flags
    }

    private fun indexOf(name: String): Int =
        runCatching { NetworkInterface.getByName(name)?.index ?: -1 }.getOrDefault(-1)

    private data class DefaultInterface(val name: String, val index: Int, val expensive: Boolean)

    private data class InterfaceMetadata(
        val type: Int,
        val metered: Boolean,
        val dnsServers: List<String>,
    )

    private companion object {
        const val TAG = "CommyNetwork"

        /** No usable default network. libbox reads index -1 as "none". */
        val ABSENT = DefaultInterface(name = "", index = -1, expensive = false)

        /**
         * The network the core rides on: one that reaches the internet and is
         * not a VPN.
         *
         * `NET_CAPABILITY_NOT_VPN` is the point of the whole request — see the
         * class comment for what following our own tunnel costs.
         */
        val WATCHED: NetworkRequest = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()

        const val FLAG_UP = 1
        const val FLAG_LOOPBACK = 4
        const val FLAG_POINT_TO_POINT = 8
        const val FLAG_MULTICAST = 16
        const val FLAG_RUNNING = 32
    }
}
