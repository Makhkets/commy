package dev.commy.app.tunnel

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
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
        current.let { listener.updateDefaultInterface(it.name, it.index, it.expensive, false) }
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
            override fun onAvailable(network: Network) = refresh(network)

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) = refresh(network)

            override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) =
                refresh(network)

            override fun onLost(network: Network) {
                if (defaultNetwork == network) {
                    setDefaultNetwork(null)
                    publish(ABSENT)
                }
            }
        }
        callback = watcher
        runCatching { manager.registerDefaultNetworkCallback(watcher) }
            .onFailure {
                callback = null
                Log.w(TAG, "cannot watch the default network: ${it.message}")
            }
    }

    private fun stopWatching() {
        val watcher = callback ?: return
        callback = null
        runCatching { connectivity?.unregisterNetworkCallback(watcher) }
    }

    private fun refresh(network: Network) {
        val manager = connectivity ?: return
        setDefaultNetwork(network)
        val name = manager.getLinkProperties(network)?.interfaceName ?: return
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
                        source.interfaceAddresses.mapNotNull { entry ->
                            entry.address.hostAddress?.let { "$it/${entry.networkPrefixLength}" }
                        },
                    ),
                )
                setFlags(goFlags(source))
                setType(extra?.type ?: Libbox.InterfaceTypeOther)
                setMetered(extra?.metered ?: false)
                setDNSServer(StringArray(extra?.dnsServers.orEmpty()))
            }
        }
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

        const val FLAG_UP = 1
        const val FLAG_LOOPBACK = 4
        const val FLAG_POINT_TO_POINT = 8
        const val FLAG_MULTICAST = 16
        const val FLAG_RUNNING = 32
    }
}
