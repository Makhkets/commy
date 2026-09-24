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
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicInteger

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

    /** Starts accepted and not yet finished, from ACTION_START to success or failure. */
    private val startsInFlight = AtomicInteger(0)

    private val bringingUp: Boolean get() = startsInFlight.get() > 0

    /**
     * Bumped by every request to stop, at the moment it is made. A start
     * remembers the value it was accepted with and gives way if it changed:
     * a stop that came after it wins, and a newer start cannot revive an older
     * one that a stop already called off.
     */
    private val stops = AtomicInteger(0)

    /** When the kill switch was last asked about while the core was up. */
    @Volatile
    private var lockdownCheckedAt = 0L

    /** [tun] is the blocking interface, with no core behind it. See [holdBlock]. */
    @Volatile
    private var blocking = false

    @Volatile
    private var lockdownWatch: Job? = null

    /** The id of the last command delivered; see [settle]. Main thread. */
    private var lastStartId = 0

    /** Held by every change of what backs the VPN slot; see [transition]. */
    private val lifecycle = Mutex()

    private val marks by lazy { TunnelMarks(applicationContext) }

    override fun onCreate() {
        super.onCreate()
        notifications = TunnelNotifications(this)
        notifications.ensureChannel()
        TunnelController.attach(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        if (intent == null) {
            reportTunnelLost()
            // Sticky whatever happens next: a service that stands down stops
            // itself, and one that holds the blocking interface wants to be
            // brought back if the process dies again.
            return START_STICKY
        }
        when (intent.action) {
            ACTION_START -> {
                // On this thread, before the launch: the lockdown watch and
                // settle() must see a start coming before it holds the lock.
                val generation = stops.get()
                startsInFlight.incrementAndGet()
                // Foreground first. Android gives a service started with
                // startForegroundService five seconds to get here, and misses
                // are a crash rather than a warning.
                goForeground(Wire.States.STARTING)
                scope.launch { bringUp(generation) }
            }
            // No foreground for the two ways down: both arrive through
            // startService, which promises nothing, and one of them lands in a
            // process that has just started — where the platform may refuse a
            // foreground start outright. shutdown() takes the notification
            // away either way.
            ACTION_STOP -> stopAsync()
            // Sent when the app finds the last process gone. If a tunnel died
            // with it, that alone is reason to ask about the kill switch: the
            // hint may predate the user turning it on mid-session.
            ACTION_CLEAR -> stopAsync(report = false, assumeLockdown = marks.tunnelUp)
            else -> {
                // Always-on VPN. The platform sends this even while a start is
                // under way ("it's not bound until after establish(), so if
                // it's mid-setup onStartCommand will be sent twice" — Vpn.java),
                // and standing down here would kill the tunnel the user just
                // asked for.
                if (isCoreUp || bringingUp || blocking) {
                    Log.i(TAG, "always-on start while the slot is already ours; ignored")
                    if (isCoreUp) {
                        // The user may have just switched the kill switch on.
                        scope.launch { rememberLockdown(force = true) }
                    }
                    return START_STICKY
                }
                goForeground(Wire.States.IDLE)
                // It hands over no configuration, and we have none to fall back
                // on: the generated config is a secret and rule R2 keeps it in
                // the encrypted store on the Dart side. Say so and stand down —
                // under the system kill switch, into the blocking interface.
                // Only the platform delivers this intent, and only to the
                // always-on app, so it is reason enough to raise the block and
                // ask whether lockdown is on.
                Log.i(TAG, "started without a configuration; asking the user to open the app")
                notifications.promptToOpenApp()
                stopAsync(assumeLockdown = true)
            }
        }
        // Sticky for the same reason as above. A command that ends in
        // stopSelf() leaves nothing to restart.
        return START_STICKY
    }

    /**
     * The system restarting us after our process died.
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
     * process died, with no intent, and standing the service down here is what
     * finally takes the stale notification away. The restart carries no
     * configuration, so the tunnel cannot come back on its own; what we can do
     * is say that it is gone, which is what the leak checklist asks for when
     * the kill switch is off (docs/09-security-privacy.md) — and, under the
     * kill switch, put the blocking interface back (ADR-0016).
     *
     * A crash is reported only if a tunnel was up ([TunnelMarks.tunnelUp]). A
     * process that died while holding only the blocking interface belonged to
     * a user who had disconnected, and telling them "the tunnel stopped" would
     * be telling them something false.
     *
     * It does not always come. On Android 16 the platform's VPN code unbinds
     * from us the moment the TUN interface disappears, which is the same
     * moment the process dies, and that unbind leaves the service record
     * behind with no restart scheduled — "Exception when unbinding service"
     * in the system log, and the stale notification with it. That case is
     * cleared from the other end, the next time the process starts: see
     * [TunnelController.clearOrphan].
     *
     * No foreground here unless the platform allows one: nothing called
     * startForegroundService, and a background restart may not be allowed it.
     */
    private fun reportTunnelLost() {
        val wasTunnel = marks.tunnelUp
        Log.w(TAG, "restarted after the process died (tunnel up: $wasTunnel)")
        scope.launch {
            // A tunnel that died is reason enough to ask about the kill
            // switch, whatever the hint says: it may have been turned on
            // while the tunnel was up.
            val held = transition { tearDownLocked(mayBlock = true, assumeLockdown = wasTunnel) }
            if (wasTunnel) {
                // The app opens on what happened, not on a quiet "Disconnected".
                TunnelController.onCoreFailure(
                    Wire.Errors.CORE_CRASHED,
                    "the process died with the tunnel up",
                )
            }
            withContext(Dispatchers.Main) {
                if (wasTunnel) {
                    notifications.tunnelLost(held)
                }
                settle(held)
            }
        }
    }

    override fun onRevoke() {
        // Another VPN app claimed the slot, or the user revoked the permission
        // in system settings. Either way it reads to the user as "grant it
        // again", which is what permission_denied puts on screen — and silence
        // here is the exact failure M1 acceptance criterion 4 names. Unless
        // nothing was running: the user left Commy disconnected behind the
        // blocking interface and moved to another VPN, which is not an error.
        if (!blocking) {
            TunnelController.onCoreFailure(
                Wire.Errors.PERMISSION_DENIED,
                "the VPN permission was revoked; another VPN app may have taken over",
            )
        }
        lockdownWatch?.cancel()
        // Whatever the kill switch said, it now belongs to someone else, and
        // an alert inviting a tap to "connect again" would take the slot back.
        notifications.clearPrompt()
        stops.incrementAndGet()
        scope.launch {
            marks.lockdown = false
            shutdown(report = false, mayBlock = false)
        }
        // No super.onRevoke(): all it does is stopSelf(), and onDestroy would
        // then release the core on this thread while the teardown above is
        // doing the same on another. The teardown stops the service itself.
    }

    override fun onDestroy() {
        // Normally releaseCore() has already run inside shutdown(). This is the
        // path where the system tore the service down under us, and leaking the
        // TUN descriptor here leaves the device with a black-hole route.
        lockdownWatch?.cancel()
        blocking = false
        releaseCore()
        runCatching { tun?.close() }
        tun = null
        TunnelController.detach(this)
        scope.cancel()
        super.onDestroy()
    }

    // ── driven by TunnelController ────────────────────────────────────────

    internal fun requestStop() {
        stopAsync()
    }

    /** Every way down goes through here, so a start accepted earlier gives way at once. */
    private fun stopAsync(
        report: Boolean = true,
        assumeLockdown: Boolean = false,
        alert: Boolean = false,
    ) {
        stops.incrementAndGet()
        scope.launch { shutdown(report = report, assumeLockdown = assumeLockdown, alert = alert) }
    }

    internal suspend fun reload(config: String) {
        // Under the lock: a reload can call openTun, and a TUN swapped under a
        // teardown in progress is a descriptor closed or lost by the wrong owner.
        transition {
            val server = commandServer ?: throw WireException(
                Wire.Errors.NOT_RUNNING,
                "reload needs a running core",
            )
            bridge?.useConfig(config)
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

    // ── one transition at a time ──────────────────────────────────────────

    /**
     * Runs [block] on the IO pool with the tunnel to itself.
     *
     * Every change of what backs the VPN slot — the core coming up, a reload,
     * a teardown, the blocking interface going up or down — goes through here.
     * They used to run side by side: a Disconnect during a start, two
     * Disconnect taps, or a crash report meeting a Disconnect each took the
     * shared descriptor from under the other, and the loser closed the live
     * interface or kept one the platform had already reset.
     */
    private suspend fun <T> transition(block: suspend () -> T): T =
        lifecycle.withLock { withContext(Dispatchers.IO) { block() } }

    // ── bringing the core up ──────────────────────────────────────────────

    private suspend fun bringUp(generation: Int) {
        try {
            transition { bringUpLocked(generation) }
        } finally {
            startsInFlight.decrementAndGet()
        }
    }

    private suspend fun bringUpLocked(generation: Int) {
        // A stop that arrived after the tap and before the lock wins: it is
        // waiting right behind this and will take down whatever is here.
        if (stops.get() != generation) {
            TunnelController.onStartAborted()
            return
        }
        stopping = false
        endBlockLocked()
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
        try {
            CoreSetup.ensure(applicationContext)
        } catch (error: Throwable) {
            failStart(WireException.from(Wire.Errors.STORAGE, error))
            return
        }
        try {
            // checkConfig before anything is allocated: a bad config caught
            // here is one typed error, caught later it is a half-built tunnel.
            Libbox.checkConfig(config)
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
            events.useConfig(config)
            events.start()
            bridge = events

            // Before the start, not after: the core's interface goes up inside
            // it, and a process that dies there has died with a tunnel up.
            marks.tunnelUp = true
            runCatching { server.startOrReloadService(config, noOverrides()) }
                .getOrElse { throw WireException.from(Wire.Errors.CONFIG_INVALID, it) }
            if (stops.get() != generation) {
                // Up, but nobody wants it any more: the stop behind the lock
                // releases it. Reporting "connected" first would flash it.
                TunnelController.onStartAborted()
                return
            }
            // After the start, not before it: see startStreams.
            events.startStreams()

            isCoreUp = true
            // Asked now, with our interface up: the only time the platform
            // answers. See TunnelMarks.
            rememberLockdown(force = true)
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
    private fun openCommandServer(): CommandServer {
        val platform = CommyPlatformInterface(this, monitor)
        val first = runCatching {
            Libbox.newCommandServer(this, platform).also { it.start() }
        }
        first.getOrNull()?.let { return it }
        val error = first.exceptionOrNull() ?: IllegalStateException("command server did not start")
        Log.w(TAG, "command server did not start on the default transport: ${error.message}")
        if (!CoreSetup.fallBackToLoopback(applicationContext)) {
            throw WireException.from(Wire.Errors.HELPER_UNAVAILABLE, error)
        }
        return runCatching {
            Libbox.newCommandServer(this, platform).also { it.start() }
        }.getOrElse { throw WireException.from(Wire.Errors.HELPER_UNAVAILABLE, it) }
    }

    /** Called with the lock held; the teardown it launches runs right after. */
    private fun failStart(error: WireException) {
        Log.w(TAG, "the tunnel did not come up: ${error.code}")
        stopping = true
        TunnelController.onStartFailed(error)
        stopAsync(report = false)
    }

    /**
     * The core went away without being asked to.
     *
     * Sitting in `connected` with a dead core is the named failure of manual
     * scenario 9, so this always produces an error state — and an alert, since
     * the app is usually closed when it happens and the error on its screen
     * reaches nobody.
     */
    private fun onCoreLost(message: String) {
        if (stopping) {
            return
        }
        stopping = true
        TunnelController.onCoreFailure(Wire.Errors.CORE_CRASHED, message)
        stopAsync(report = false, alert = true)
    }

    private fun onTraffic(up: Long, down: Long) {
        if (!isCoreUp) {
            return
        }
        notifications.update(Wire.States.CONNECTED, bridge?.selectedNode, up, down)
        // Rides the once-a-second tick: the kill switch can be turned on
        // mid-session, and the platform answers only while our VPN is up.
        rememberLockdown(force = false)
    }

    /** Records what the kill switch says now, while our VPN is up to be answered. */
    private fun rememberLockdown(force: Boolean) {
        val now = System.currentTimeMillis()
        if (!force && now - lockdownCheckedAt < LOCKDOWN_REFRESH_MS) {
            return
        }
        lockdownCheckedAt = now
        marks.lockdown = isLockedDown()
    }

    // ── taking it down ────────────────────────────────────────────────────

    /**
     * Takes the core down, and the service with it — or, under the system
     * kill switch and unless [mayBlock] is false, leaves the blocking
     * interface in its place (see [holdBlock]).
     *
     * [alert] posts "the tunnel stopped" on the alerts channel: for the ways
     * down the user did not ask for.
     */
    private suspend fun shutdown(
        report: Boolean = true,
        mayBlock: Boolean = true,
        assumeLockdown: Boolean = false,
        alert: Boolean = false,
    ) {
        stopping = true
        val held = transition { tearDownLocked(mayBlock, assumeLockdown) }
        if (report) {
            TunnelController.onStopped()
        }
        withContext(Dispatchers.Main) {
            if (alert) {
                notifications.tunnelLost(held)
            }
            settle(held)
        }
    }

    /**
     * Releases the core and leaves the slot either empty or blocking.
     * Returns whether the blocking interface is up afterwards.
     *
     * The blocking interface is established before the core's is released, so
     * there is no moment with no VPN at all: in that moment Android lets DNS
     * out in the clear.
     */
    private fun tearDownLocked(mayBlock: Boolean, assumeLockdown: Boolean): Boolean {
        if (mayBlock && blocking && !isCoreUp && tun != null) {
            val lockedDown = isLockedDown()
            marks.lockdown = lockedDown
            if (lockedDown) {
                return true
            }
        }
        val block = if (mayBlock) raiseBlockIfLockedDown(assumeLockdown) else null
        val previous = tun
        tun = null
        releaseCore()
        if (previous != null && previous !== block) {
            runCatching { previous.close() }
        }
        tun = block
        blocking = block != null
        marks.tunnelUp = false
        return block != null
    }

    /**
     * The blocking interface, if the system kill switch is on; null otherwise.
     *
     * The platform answers "is lockdown on?" only for an app whose VPN is up
     * right now. With our interface up, it is simply asked. Without one — after
     * a process death, from a failed first start, on an always-on start — the
     * block is raised first and the question asked with it up; if the answer
     * is no, it comes straight down. That costs a user without the kill switch
     * one establish-and-close, and only when [TunnelMarks.lockdown] or
     * [assumeLockdown] says it is worth asking.
     */
    private fun raiseBlockIfLockedDown(assumeLockdown: Boolean): ParcelFileDescriptor? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // No way to ask below Android 10; nothing to raise.
            return null
        }
        if (tun != null) {
            val lockedDown = isLockedDown()
            marks.lockdown = lockedDown
            return if (lockedDown) establishBlock() else null
        }
        if (!assumeLockdown && !marks.lockdown) {
            return null
        }
        val block = establishBlock() ?: return null
        val lockedDown = isLockedDown()
        marks.lockdown = lockedDown
        if (lockedDown) {
            return block
        }
        runCatching { block.close() }
        return null
    }

    /**
     * Main thread: shows the outcome of a transition that has already
     * happened — the blocking notification, or the service going away.
     *
     * Checks the state again rather than trusting [held]: a start queued
     * behind the teardown may already own the slot, and it posted its own
     * notification.
     */
    private fun settle(held: Boolean) {
        if (bringingUp || isCoreUp) {
            return
        }
        if (held && blocking) {
            holdBlock()
            return
        }
        if (blocking) {
            return
        }
        notifications.cancel()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        // The id of the last command we saw: a start the platform has
        // accepted since then keeps the service alive.
        stopSelf(lastStartId)
    }

    // ── the blocking interface ────────────────────────────────────────────

    /**
     * Keeps a TUN up with no core behind it, while the system kill switch is on.
     *
     * "Always-on VPN" + "Block connections without VPN" stops every app's
     * connections when no VPN is up, but not their names: DNS is sent by netd
     * as uid 0, which Android exempts from the block, so with the tunnel down
     * every lookup went out to the network's resolver in the clear
     * (docs/09-security-privacy.md, session 16 run; Mullvad reported the same
     * in 2024). A VPN that is up takes the device's DNS with it, so this one is
     * up: a default route and a resolver inside the interface, and nothing
     * reading it — every packet, lookups included, stops here.
     *
     * Only under the kill switch, where the user has already chosen "no
     * network without the VPN": this closes the one thing that choice leaked
     * and changes nothing else about "Disconnect". Without it, Disconnect
     * still hands the network straight back. ADR-0016.
     *
     * Ends when a tunnel starts (its interface replaces this one before this
     * one closes — see [openTun]), when the kill switch is turned off
     * ([watchLockdown]), or when another VPN takes the slot ([onRevoke]).
     *
     * Main thread; the interface itself is already up ([tearDownLocked]).
     */
    private fun holdBlock() {
        val notification = notifications.blocked()
        val foreground = runCatching { startForegroundCompat(notification) }
        if (foreground.isFailure) {
            Log.w(TAG, "blocking without a foreground notification: ${foreground.exceptionOrNull()}")
            notifications.showBlocked()
        }
        watchLockdown()
    }

    /**
     * Lets the blocking interface go once the kill switch is off.
     *
     * The platform says nothing when the user turns it off, and it will not
     * restart an always-on VPN that is already established, so this asks. A
     * block that outlived the setting would be a device with no network and no
     * reason for it. Polled rather than observed: the settings behind it are
     * hidden, and the question is one binder call every few seconds while
     * nothing else runs.
     */
    private fun watchLockdown() {
        lockdownWatch?.cancel()
        lockdownWatch = scope.launch {
            while (isActive) {
                delay(LOCKDOWN_POLL_MS)
                val released = transition {
                    if (!blocking || isCoreUp || bringingUp) {
                        return@transition null
                    }
                    val lockedDown = isLockedDown()
                    marks.lockdown = lockedDown
                    if (lockedDown) {
                        return@transition false
                    }
                    Log.i(TAG, "the system kill switch is off; releasing the blocking interface")
                    // Not endBlockLocked(): that cancels this very coroutine,
                    // and the notification and the service were then left
                    // behind at the next suspension point (seen on the
                    // emulator: "network closed" over a working network).
                    blocking = false
                    runCatching { tun?.close() }
                    tun = null
                    true
                } ?: break
                if (released) {
                    withContext(Dispatchers.Main) {
                        // An alert saying "nothing reaches the network" is
                        // now the opposite of the truth.
                        notifications.clearPrompt()
                        settle(held = false)
                    }
                    break
                }
            }
        }
    }

    /** With the lock held. Leaves [tun] alone: whoever ends the block decides what closes it. */
    private fun endBlockLocked() {
        lockdownWatch?.cancel()
        blocking = false
    }

    /**
     * A TUN that goes nowhere: default routes and a resolver inside it, the
     * physical network hidden from apps, and our own package left outside so
     * subscriptions and pings still work. Null when the VPN permission is gone.
     */
    private fun establishBlock(): ParcelFileDescriptor? = runCatching<ParcelFileDescriptor?> {
        val builder = Builder()
            .setSession(getString(R.string.app_name))
            .setMtu(BLOCK_MTU)
            .setConfigureIntent(configureIntent())
            // An empty set says "connected to nothing": apps that ask the
            // system whether there is internet get no, instead of waiting out
            // timeouts against a route that swallows everything.
            .setUnderlyingNetworks(emptyArray<Network>())
            .addAddress(BLOCK_V4, BLOCK_V4_PREFIX)
            .addRoute(DEFAULT_V4, 0)
            .addDnsServer(BLOCK_V4_DNS)
            .addAddress(BLOCK_V6, BLOCK_V6_PREFIX)
            .addRoute(DEFAULT_V6, 0)
            .addDnsServer(BLOCK_V6_DNS)
        runCatching { builder.addDisallowedApplication(packageName) }
        builder.establish()
    }.onFailure {
        Log.w(TAG, "could not raise the blocking interface: ${it.message}")
    }.getOrNull()

    /**
     * Whether the system kill switch is on. Meaningful only while our VPN is
     * up: without one the platform answers false whatever the setting is.
     */
    private fun isLockedDown(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            runCatching { isAlwaysOn && isLockdownEnabled }.getOrDefault(false)

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
        startForegroundCompat(notifications.build(state, bridge?.selectedNode, 0, 0))
    }

    private fun startForegroundCompat(notification: Notification) {
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

        // The same private ranges sing-box gives its own TUN, so the blocking
        // interface never claims an address a user's network could be using.
        private const val BLOCK_V4 = "172.19.0.1"
        private const val BLOCK_V4_PREFIX = 30
        private const val BLOCK_V4_DNS = "172.19.0.2"
        private const val BLOCK_V6 = "fdfe:dcba:9876::1"
        private const val BLOCK_V6_PREFIX = 126
        private const val BLOCK_V6_DNS = "fdfe:dcba:9876::2"
        private const val BLOCK_MTU = 1500

        private const val LOCKDOWN_POLL_MS = 5_000L
        private const val LOCKDOWN_REFRESH_MS = 30_000L
    }
}
