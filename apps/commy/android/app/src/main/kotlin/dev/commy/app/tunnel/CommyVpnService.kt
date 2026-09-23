package dev.commy.app.tunnel

import android.app.Notification
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.IpPrefix
import android.net.Network
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.ServiceCompat
import dev.commy.app.MainActivity
import dev.commy.app.R
import dev.commy.app.wire.Wire
import dev.commy.app.wire.WireException
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.InetAddress

/**
 * The tunnel.
 *
 * Four responsibilities and no fifth: get a TUN descriptor, implement
 * `PlatformInterface`, own the service lifecycle, show the system UI. No
 * subscription parsing, no config building, no deciding which apps are
 * tunnelled. Routes and package lists arrive already computed inside
 * [TunOptions]; translating them into a `VpnService.Builder` is all that
 * happens here (docs/02-architecture.md).
 *
 * The sequence that brings a tunnel up, and the one detail every
 * reconstruction from memory gets wrong: **there is no `NewService`.**
 *
 * ```
 * Libbox.setup(SetupOptions)                     once per process
 * Libbox.newCommandServer(handler, platform)
 * commandServer.start()
 * commandServer.startOrReloadService(json, OverrideOptions()) ← the tunnel
 *     │                                        comes up here
 *     └─ calls back into PlatformInterface.openTun(), which is where the
 *        VpnService.Builder is assembled and the fd handed over
 * ```
 *
 * The second argument is never `null`, whatever the Java signature allows.
 * libbox reads `options.AutoRedirect` with no nil check (command_server.go,
 * sing-box 1.13), so `null` is a nil-pointer panic inside Go — and the core
 * lives in this process, so the panic takes the app down with it. That was the
 * first thing a real device ever said about this service: every connect
 * crashed. See [noOverrides].
 */
class CommyVpnService : VpnService(), CommandServerHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    internal lateinit var notifications: TunnelNotifications
        private set

    private val monitor by lazy { DefaultNetworkMonitor(this) }

    private val doze by lazy { DozeMonitor(this, scope) }

    private var commandServer: CommandServer? = null
    private var bridge: CoreEventBridge? = null
    private var tun: ParcelFileDescriptor? = null

    @Volatile
    internal var isCoreUp: Boolean = false
        private set

    /** Set before any deliberate teardown, so the core's own stop is not read as a crash. */
    @Volatile
    private var stopping = false

    override fun onCreate() {
        super.onCreate()
        notifications = TunnelNotifications(this)
        notifications.ensureChannel()
        TunnelController.attach(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            reportTunnelLost(startId)
            return START_NOT_STICKY
        }
        when (intent.action) {
            ACTION_START -> {
                // Foreground first. Android gives a service started with
                // startForegroundService five seconds to get here, and misses
                // are a crash rather than a warning.
                goForeground(Wire.States.STARTING)
                scope.launch { bringUp() }
            }
            // No foreground for the two ways down: both arrive through
            // startService, which promises nothing, and one of them lands in a
            // process that has just started — where the platform may refuse a
            // foreground start outright. shutdown() takes the notification
            // away either way.
            ACTION_STOP -> scope.launch { shutdown() }
            ACTION_CLEAR -> scope.launch { shutdown(report = false) }
            else -> {
                goForeground(Wire.States.IDLE)
                // Always-on VPN. It hands over no configuration, and we have
                // none to fall back on: the generated config is a secret and
                // rule R2 keeps it in the encrypted store on the Dart side.
                // Say so and stand down.
                Log.i(TAG, "started without a configuration; asking the user to open the app")
                notifications.promptToOpenApp()
                scope.launch { shutdown() }
            }
        }
        // STICKY only while a tunnel is coming up, and for one reason: to be
        // told when it dies. See [reportTunnelLost].
        return if (intent.action == ACTION_START) START_STICKY else START_NOT_STICKY
    }

    /**
     * The system restarting us after our process died with the tunnel up.
     *
     * The core lives in this process, so a Go panic, the low-memory killer or
     * anything else that ends the process ends the tunnel too — and Android
     * does not take down the notification with it. The service record outlives
     * the process, and so does the last thing it posted: "Connected", with a
     * speed, above a Disconnect button, while every app is back on the open
     * network. That is the one thing a proxy client must never tell its user,
     * and it stayed there until something started the process again.
     *
     * START_STICKY is how we find out. Android restarts a sticky service whose
     * process died, with no intent, and stopping the service here is what
     * finally takes the stale notification away. The restart carries no
     * configuration, so the tunnel cannot come back on its own; what we can do
     * is say that it is gone, which is what the leak checklist asks for when
     * the kill switch is off (docs/09-security-privacy.md).
     *
     * It does not always come. On Android 16 the platform's VPN code unbinds
     * from us the moment the TUN interface disappears, which is the same
     * moment the process dies, and that unbind leaves the service record
     * behind with no restart scheduled — "Exception when unbinding service"
     * in the system log, and the stale notification with it. That case is
     * cleared from the other end, the next time the process starts: see
     * [TunnelController.clearOrphan].
     *
     * No foreground here: nothing called startForegroundService, and a
     * background restart may not be allowed one.
     */
    private fun reportTunnelLost(startId: Int) {
        Log.w(TAG, "restarted after the process died with the tunnel up")
        val blocked = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            runCatching { isLockdownEnabled }.getOrDefault(false)
        notifications.tunnelLost(blocked)
        stopSelf(startId)
    }

    override fun onRevoke() {
        // Another VPN app claimed the slot, or the user revoked the permission
        // in system settings. Either way it reads to the user as "grant it
        // again", which is what permission_denied puts on screen — and silence
        // here is the exact failure M1 acceptance criterion 4 names.
        TunnelController.onCoreFailure(
            Wire.Errors.PERMISSION_DENIED,
            "the VPN permission was revoked; another VPN app may have taken over",
        )
        stopping = true
        scope.launch { shutdown(report = false) }
        super.onRevoke()
    }

    override fun onDestroy() {
        // Normally releaseCore() has already run inside shutdown(). This is the
        // path where the system tore the service down under us, and leaking the
        // TUN descriptor here leaves the device with a black-hole route.
        releaseCore()
        TunnelController.detach(this)
        scope.cancel()
        super.onDestroy()
    }

    // ── driven by TunnelController ────────────────────────────────────────

    internal fun requestStop() {
        scope.launch { shutdown() }
    }

    internal suspend fun reload(config: String) {
        val server = commandServer ?: throw WireException(
            Wire.Errors.NOT_RUNNING,
            "reload needs a running core",
        )
        withContext(Dispatchers.IO) {
            runCatching { server.startOrReloadService(config, noOverrides()) }
                .getOrElse { throw WireException.from(Wire.Errors.CONFIG_INVALID, it) }
        }
    }

    internal suspend fun select(group: String, tag: String) {
        requireBridge().select(group, tag)
    }

    internal suspend fun urlTest(group: String, tag: String, timeoutMs: Long): Long? =
        requireBridge().urlTest(group, tag, timeoutMs)

    internal fun proxies(): String = bridge?.proxies() ?: CoreSnapshots.NO_GROUPS

    // ── bringing the core up ──────────────────────────────────────────────

    private suspend fun bringUp() {
        val config = TunnelController.takePendingConfig()
        if (config == null) {
            failStart(
                WireException(
                    Wire.Errors.HELPER_UNAVAILABLE,
                    "the tunnel service was started without a configuration",
                ),
            )
            return
        }
        stopping = false
        try {
            CoreSetup.ensure(applicationContext)
        } catch (error: Throwable) {
            failStart(WireException.from(Wire.Errors.STORAGE, error))
            return
        }
        try {
            // checkConfig before anything is allocated: a bad config caught
            // here is one typed error, caught later it is a half-built tunnel.
            withContext(Dispatchers.IO) { Libbox.checkConfig(config) }
        } catch (error: Throwable) {
            failStart(WireException.from(Wire.Errors.CONFIG_INVALID, error))
            return
        }
        try {
            val server = openCommandServer()
            commandServer = server
            monitor.attach(server)
            // Tells the system which physical network our tunnel is riding on,
            // so data-usage attribution and every app's "am I on Wi-Fi" answer
            // follow the handover instead of freezing at whatever was true when
            // the tunnel came up.
            monitor.onDefaultNetworkChanged = ::publishUnderlyingNetwork
            publishUnderlyingNetwork(monitor.defaultNetwork)
            doze.attach(server)

            val events = CoreEventBridge(scope, ::onCoreLost, ::onTraffic)
            events.start()
            bridge = events

            withContext(Dispatchers.IO) {
                runCatching { server.startOrReloadService(config, noOverrides()) }
                    .getOrElse { throw WireException.from(Wire.Errors.CONFIG_INVALID, it) }
            }
            // After the start, not before it: see startStreams.
            events.startStreams()

            isCoreUp = true
            // getStartedAt comes from the core and is the honest answer; the
            // clock reading is only a fallback. Either way it is recorded once
            // — the on-screen uptime hangs off it and must not jump.
            val since = events.startedAtMillis() ?: System.currentTimeMillis()
            TunnelController.onStarted(since)
            notifications.update(Wire.States.CONNECTED, events.selectedNode, 0, 0)
            notifications.clearPrompt()
        } catch (error: Throwable) {
            val failure = error as? WireException
                ?: WireException.from(Wire.Errors.CORE_CRASHED, error)
            failStart(failure)
        }
    }

    /**
     * Starts the command server, retrying once on a different transport.
     *
     * The default transport is a unix socket inside our private directory,
     * which is both the right answer and an inference about libbox's behaviour
     * when no port is configured. If it turns out to be wrong on some device,
     * the retry moves the server to authenticated loopback rather than leaving
     * the user with a tunnel that will not start. See [CoreSetup].
     */
    private suspend fun openCommandServer(): CommandServer = withContext(Dispatchers.IO) {
        val platform = CommyPlatformInterface(this@CommyVpnService, monitor)
        val first = runCatching {
            Libbox.newCommandServer(this@CommyVpnService, platform).also { it.start() }
        }
        first.getOrNull()?.let { return@withContext it }
        val error = first.exceptionOrNull() ?: IllegalStateException("command server did not start")
        Log.w(TAG, "command server did not start on the default transport: ${error.message}")
        if (!CoreSetup.fallBackToLoopback(applicationContext)) {
            throw WireException.from(Wire.Errors.HELPER_UNAVAILABLE, error)
        }
        runCatching {
            Libbox.newCommandServer(this@CommyVpnService, platform).also { it.start() }
        }.getOrElse { throw WireException.from(Wire.Errors.HELPER_UNAVAILABLE, it) }
    }

    private fun failStart(error: WireException) {
        Log.w(TAG, "the tunnel did not come up: ${error.code}")
        stopping = true
        TunnelController.onStartFailed(error)
        scope.launch { shutdown(report = false) }
    }

    /**
     * The core went away without being asked to.
     *
     * Sitting in `connected` with a dead core is the named failure of manual
     * scenario 9, so this always produces an error state.
     */
    private fun onCoreLost(message: String) {
        if (stopping) {
            return
        }
        stopping = true
        TunnelController.onCoreFailure(Wire.Errors.CORE_CRASHED, message)
        scope.launch { shutdown(report = false) }
    }

    private fun onTraffic(up: Long, down: Long) {
        if (!isCoreUp) {
            return
        }
        notifications.update(Wire.States.CONNECTED, bridge?.selectedNode, up, down)
    }

    // ── taking it down ────────────────────────────────────────────────────

    private suspend fun shutdown(report: Boolean = true) {
        stopping = true
        withContext(Dispatchers.IO) { releaseCore() }
        if (report) {
            TunnelController.onStopped()
        }
        withContext(Dispatchers.Main) {
            notifications.cancel()
            ServiceCompat.stopForeground(this@CommyVpnService, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    /** Synchronous, idempotent, safe to call twice. */
    private fun releaseCore() {
        isCoreUp = false
        runCatching { bridge?.close() }
        bridge = null
        runCatching { doze.close() }
        runCatching { commandServer?.closeService() }
        runCatching { commandServer?.close() }
        commandServer = null
        monitor.onDefaultNetworkChanged = null
        runCatching { monitor.close() }
        runCatching { tun?.close() }
        tun = null
    }

    /**
     * Reports the physical network underneath the tunnel.
     *
     * Null hands the decision back to the platform, which is the honest answer
     * while there is no default network at all: claiming the one that just went
     * away would have the system attribute traffic to a dead interface.
     */
    private fun publishUnderlyingNetwork(network: Network?) {
        runCatching { setUnderlyingNetworks(network?.let { arrayOf(it) }) }
    }

    // ── PlatformInterface.openTun, which is why this class exists ─────────

    /**
     * Turns [TunOptions] into a live TUN descriptor.
     *
     * Every value here was computed by sing-box. Nothing is invented: not the
     * routes, not the exclusions, not the package lists. The one thing added is
     * our own package in the disallow list, and that is not policy — a client
     * whose own traffic goes through the tunnel it is building cannot fetch the
     * subscription that would fix it.
     */
    internal fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession(getString(R.string.app_name))
            .setMtu(options.getMTU())
            .setConfigureIntent(configureIntent())

        val v4 = options.inet4Address.drain()
        val v6 = options.inet6Address.drain()
        for (address in v4 + v6) {
            builder.addAddress(address.address, address.length)
        }

        if (options.autoRoute) {
            runCatching { builder.addDnsServer(options.getDNSServerAddress().value) }
            addRoutes(builder, options, hasV4 = v4.isNotEmpty(), hasV6 = v6.isNotEmpty())
        } else {
            for (route in options.inet4RouteAddress.drain() + options.inet6RouteAddress.drain()) {
                builder.addRoute(route.address, route.length)
            }
        }

        applyPackages(builder, options)
        applyHttpProxy(builder, options)

        val descriptor = builder.establish()
            ?: throw IllegalStateException(
                "VpnService.Builder.establish() returned null: the VPN permission is not held",
            )
        // The descriptor stays ours. Go reads the raw fd, and closing this
        // ParcelFileDescriptor on teardown is what actually tears the interface
        // down — handing over detachFd() instead leaks it for the process life.
        runCatching { tun?.close() }
        tun = descriptor
        return descriptor.fd
    }

    private fun addRoutes(
        builder: Builder,
        options: TunOptions,
        hasV4: Boolean,
        hasV6: Boolean,
    ) {
        // RouteRange, not RouteAddress. sing-box computes the range with the
        // exclusions already subtracted, which is the whole reason it exists;
        // reaching for 0.0.0.0/0 here undoes every "do not tunnel this" rule
        // the user set, silently.
        val ranges = options.inet4RouteRange.drain() + options.inet6RouteRange.drain()
        if (ranges.isEmpty()) {
            if (hasV4) {
                builder.addRoute(DEFAULT_V4, 0)
            }
            if (hasV6) {
                builder.addRoute(DEFAULT_V6, 0)
            }
        } else {
            for (route in ranges) {
                builder.addRoute(route.address, route.length)
            }
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        // Android 13 can express an exclusion directly, which is more precise
        // than the subtracted range and survives a later route being added.
        val excluded = options.inet4RouteExcludeAddress.drain() +
            options.inet6RouteExcludeAddress.drain()
        for (route in excluded) {
            runCatching {
                builder.excludeRoute(IpPrefix(InetAddress.getByName(route.address), route.length))
            }
        }
    }

    private fun applyPackages(builder: Builder, options: TunOptions) {
        val self = packageName
        // Allow list and deny list are mutually exclusive in VpnService.Builder
        // — mixing them throws. Which one is in play was decided in the config
        // by commy_config; this only reads the answer.
        val included = options.includePackage.drain().filterNot { it == self }
        if (included.isNotEmpty()) {
            for (name in included) {
                // An app the user selected and then uninstalled throws
                // NameNotFoundException. Dropping it silently is right: the
                // alternative is a tunnel that refuses to start over a stale
                // row in a picker.
                runCatching { builder.addAllowedApplication(name) }
            }
            // Nothing to exclude: leaving our package out of the allow list
            // already keeps it off the tunnel.
            return
        }
        val excluded = LinkedHashSet(options.excludePackage.drain()).apply { add(self) }
        for (name in excluded) {
            runCatching { builder.addDisallowedApplication(name) }
        }
    }

    private fun applyHttpProxy(builder: Builder, options: TunOptions) {
        if (!options.isHTTPProxyEnabled() || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return
        }
        runCatching {
            builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    options.getHTTPProxyServer(),
                    options.getHTTPProxyServerPort(),
                    options.getHTTPProxyBypassDomain().drain(),
                ),
            )
        }
    }

    // ── CommandServerHandler ──────────────────────────────────────────────

    /**
     * A client asked the core to reload.
     *
     * Ours never does: `reload` on the method channel goes straight to
     * `startOrReloadService` with a freshly built config, because the config is
     * always regenerated whole and never patched.
     */
    override fun serviceReload() = Unit

    override fun serviceStop() {
        // The core stopping itself, when we did not ask, is a crash by another
        // name.
        onCoreLost("the core stopped the service")
    }

    /** Android has no per-app system proxy an app may set. */
    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus().apply {
        setAvailable(false)
        setEnabled(false)
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) = Unit

    /**
     * The core's own copy of a line it has already sent us.
     *
     * Not forwarded to the app, and that is the fix rather than an oversight.
     * `StartedService.WriteMessage` emits every line to the log subscriber —
     * which is what `CoreEventBridge` is subscribed to, with the real severity
     * attached — and *then*, in a debug build only, hands the same text here
     * with no level at all. Forwarding it put every line on the log screen
     * twice, and labelled the second copy `debug` whatever it actually was, so
     * an error and a routing note read the same. A log that says everything
     * twice and grades none of it is the log the owner was looking at when they
     * said there was nothing useful in it.
     *
     * logcat is the right home for it: it costs nothing in release (this is
     * never called), and it gives `adb logcat -s CommyCore` to whoever is
     * holding the device.
     */
    override fun writeDebugMessage(message: String) {
        Log.d("CommyCore", message)
    }

    // ── system UI plumbing ────────────────────────────────────────────────

    private fun goForeground(state: String) {
        val notification = notifications.build(state, bridge?.selectedNode, 0, 0)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(TunnelNotifications.ID_TUNNEL, notification)
            return
        }
        startForegroundTyped(notification)
    }

    /**
     * Android 14 made the foreground service type mandatory and never added one
     * for VPNs.
     *
     * `systemExempted` is what the reference sing-box client ships and what the
     * platform grants an app holding the VPN slot. `specialUse` is the
     * documented "not in the list" type. Both are declared in the manifest and
     * we try them in that order, because the exemption is decided by the
     * platform at call time and a `ForegroundServiceTypeNotAllowedException`
     * here is a tunnel that never starts, on a device we cannot test.
     */
    private fun startForegroundTyped(notification: Notification) {
        val types = intArrayOf(
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
        )
        for (type in types) {
            val started = runCatching {
                ServiceCompat.startForeground(
                    this,
                    TunnelNotifications.ID_TUNNEL,
                    notification,
                    type,
                )
            }
            if (started.isSuccess) {
                return
            }
            Log.w(TAG, "foreground service type $type refused: ${started.exceptionOrNull()}")
        }
        // Last resort. On API 34+ this throws too, but the exception naming the
        // missing type is far more useful than a silent no-op service.
        startForeground(TunnelNotifications.ID_TUNNEL, notification)
    }

    private fun configureIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Override options that override nothing.
     *
     * An object, never `null` — see the class comment for what `null` costs.
     * Empty is also the right content: libbox *appends* these package lists to
     * the ones in the config, and the config is where ours already are
     * (`commy_config` writes `include_package` / `exclude_package` into the TUN
     * inbound). `autoRedirect` stays false; it needs root, and we never ask
     * for it.
     */
    private fun noOverrides(): OverrideOptions = OverrideOptions()

    private fun requireBridge(): CoreEventBridge = bridge
        ?: throw WireException(Wire.Errors.NOT_RUNNING, "the core is not running")

    companion object {
        private const val TAG = "CommyVpn"

        const val ACTION_START = "dev.commy.app.action.START"
        const val ACTION_STOP = "dev.commy.app.action.STOP"

        /** [ACTION_STOP] for a service whose process already died. */
        const val ACTION_CLEAR = "dev.commy.app.action.CLEAR"

        private const val DEFAULT_V4 = "0.0.0.0"
        private const val DEFAULT_V6 = "::"
    }
}
