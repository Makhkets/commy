package dev.commy.app.tunnel

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import dev.commy.app.wire.Wire
import dev.commy.app.wire.WireException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The seam between the method channel and the tunnel service.
 *
 * A process-wide object rather than a binding, because the service and the
 * Flutter engine live in the same process (docs/03-platform-tunnel.md: no
 * process boundary on Android) and because it has to outlive the engine. A hot
 * restart, or the user dismissing the app and coming back, destroys the engine
 * and builds a new one on top of a tunnel that never stopped; the state it
 * re-subscribes to has to still be here.
 *
 * The trade-off that buys: a Go panic takes the UI down with it, where the
 * upstream sing-box client isolates the core in a `:box` process. Recovering
 * that isolation means AIDL and a second Flutter-free entry point, and is a
 * decision for a later milestone — noted in android/README.md.
 *
 * ## What it deliberately does not hold
 *
 * The configuration. It passes through on the way to the service and is dropped
 * the moment the core has it. The generated config carries every credential the
 * user owns, rule R2 keeps it in the encrypted store on the Dart side, and a
 * copy cached here "so boot can reconnect" would quietly undo that.
 */
internal object TunnelController {

    private const val TAG = "CommyTunnel"

    /** How long `start` waits for the service to report back. */
    private const val START_TIMEOUT_MS = 30_000L

    /** How long `stop` waits for the core to wind down before answering anyway. */
    private const val STOP_TIMEOUT_MS = 10_000L

    private val statusState = MutableStateFlow(StatusEvent.IDLE)

    /**
     * `/status`.
     *
     * A `StateFlow` on purpose: the protocol requires the current state to be
     * delivered the instant Dart subscribes, and a state flow does that by
     * construction instead of by remembering to.
     */
    val status: Flow<String> = statusState.map(StatusEvent::toJson)

    private val trafficFlow = events()
    private val logsFlow = events()
    private val connectionsFlow = events()

    val traffic: Flow<String> = trafficFlow.asSharedFlow()
    val logs: Flow<String> = logsFlow.asSharedFlow()
    val connections: Flow<String> = connectionsFlow.asSharedFlow()

    @Volatile
    private var service: CommyVpnService? = null

    private val lock = Any()
    private var pendingConfig: String? = null
    private var startGate: CompletableDeferred<Unit>? = null
    private var stopGate: CompletableDeferred<Unit>? = null

    val isRunning: Boolean get() = service?.isCoreUp == true

    val state: String get() = statusState.value.state

    // ── called from the method channel ────────────────────────────────────

    /**
     * Brings the tunnel up.
     *
     * Answers `already_running` rather than restarting. The protocol allows
     * either, and Dart reads that code as success, so a double tap on Connect
     * does nothing visible — which is the point of the double-start acceptance
     * test. Changing the running configuration is `reload`, and changing the
     * node is `select`; neither of them belongs here.
     */
    suspend fun start(context: Context, config: String) {
        if (isRunning) {
            throw WireException(Wire.Errors.ALREADY_RUNNING, "the tunnel is already up")
        }
        val gate = CompletableDeferred<Unit>()
        synchronized(lock) {
            pendingConfig = config
            startGate = gate
        }
        statusState.value = StatusEvent.STARTING
        try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, CommyVpnService::class.java)
                    .setAction(CommyVpnService.ACTION_START),
            )
        } catch (error: Throwable) {
            forget()
            fail(Wire.Errors.HELPER_UNAVAILABLE, error.message.orEmpty())
            throw WireException.from(Wire.Errors.HELPER_UNAVAILABLE, error)
        }
        try {
            withTimeout(START_TIMEOUT_MS) { gate.await() }
        } catch (error: TimeoutCancellationException) {
            forget()
            service?.requestStop()
            val message = "the tunnel service did not report back in ${START_TIMEOUT_MS}ms"
            fail(Wire.Errors.HELPER_UNAVAILABLE, message)
            throw WireException(Wire.Errors.HELPER_UNAVAILABLE, message, error)
        }
    }

    /** Takes the tunnel down. Stopping an already stopped tunnel is a success. */
    suspend fun stop() {
        val running = service
        if (running == null) {
            statusState.value = StatusEvent.IDLE
            return
        }
        val gate = CompletableDeferred<Unit>()
        synchronized(lock) { stopGate = gate }
        statusState.value = StatusEvent.STOPPING
        running.requestStop()
        withTimeoutOrNull(STOP_TIMEOUT_MS) { gate.await() }
        synchronized(lock) { stopGate = null }
        // Reported idle even on timeout. A core that will not wind down is a
        // bug worth a log line, but leaving the UI stuck on "disconnecting"
        // with no way out is worse than being optimistic here.
        statusState.value = StatusEvent.IDLE
    }

    suspend fun reload(config: String) {
        val running = service ?: throw notRunning("reload")
        running.reload(config)
    }

    suspend fun select(group: String, tag: String) {
        val running = service ?: throw notRunning("select")
        running.select(group, tag)
    }

    /**
     * Measures one outbound.
     *
     * Returns null for "the probe did not come back", which is not an error:
     * an unreachable node and a broken app have to look different, and
     * `MeasureLatencyUseCase` draws a dash for null.
     */
    suspend fun urlTest(group: String, tag: String, timeoutMs: Long): Long? {
        val running = service ?: throw notRunning(Wire.Methods.URL_TEST)
        return running.urlTest(group, tag, timeoutMs)
    }

    /** The last groups the core reported, or an empty array when it is not up. */
    fun proxies(): String = service?.proxies() ?: CoreSnapshots.NO_GROUPS

    // ── called from the service ───────────────────────────────────────────

    fun attach(instance: CommyVpnService) {
        service = instance
    }

    fun detach(instance: CommyVpnService) {
        if (service === instance) {
            service = null
        }
        synchronized(lock) {
            stopGate?.complete(Unit)
            stopGate = null
        }
    }

    /**
     * Hands the configuration to the service exactly once.
     *
     * Cleared on read: it is a secret, and the shorter it is reachable the
     * better. A service started without one — always-on VPN, a system restart —
     * gets null and says so.
     */
    fun takePendingConfig(): String? = synchronized(lock) {
        val config = pendingConfig
        pendingConfig = null
        config
    }

    fun onStarted(since: Long) {
        statusState.value = StatusEvent.connected(since)
        synchronized(lock) {
            startGate?.complete(Unit)
            startGate = null
        }
    }

    fun onStartFailed(error: WireException) {
        statusState.value = StatusEvent.error(error.code, error.detail)
        synchronized(lock) {
            startGate?.completeExceptionally(error)
            startGate = null
        }
    }

    fun onStopped() {
        statusState.value = StatusEvent.IDLE
        synchronized(lock) {
            stopGate?.complete(Unit)
            stopGate = null
        }
    }

    /**
     * The core went away without being asked to.
     *
     * An external kill, a Go panic, a `serviceStop` we did not initiate, or the
     * system revoking the VPN. Sitting in `connected` with a dead core is the
     * named failure of manual scenario 9, so this always lands as an error
     * state even if nothing is listening at the time.
     */
    fun onCoreFailure(code: String, reason: String) {
        Log.w(TAG, "core failure: $code")
        fail(code, reason)
        synchronized(lock) {
            startGate?.completeExceptionally(WireException(code, reason))
            startGate = null
            stopGate?.complete(Unit)
            stopGate = null
        }
    }

    fun emitTraffic(json: String) {
        trafficFlow.tryEmit(json)
    }

    fun emitLogs(json: String) {
        logsFlow.tryEmit(json)
    }

    fun emitConnections(json: String) {
        connectionsFlow.tryEmit(json)
    }

    // ── internals ─────────────────────────────────────────────────────────

    private fun fail(code: String, reason: String) {
        statusState.value = StatusEvent.error(code, reason)
    }

    private fun forget() = synchronized(lock) {
        pendingConfig = null
        startGate = null
    }

    private fun notRunning(what: String) =
        WireException(Wire.Errors.NOT_RUNNING, "$what needs a running core")

    /**
     * A hot event stream.
     *
     * `DROP_OLDEST` rather than back pressure: these are samples of a live
     * system, and a slow subscriber should see the recent ones, not stall the
     * Go thread that produced them. `tryEmit` never blocks with this policy,
     * which is what makes it safe to call from a libbox callback.
     */
    private fun events() = MutableSharedFlow<String>(
        replay = 0,
        extraBufferCapacity = 16,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
}
