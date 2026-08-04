package dev.commy.app.tunnel

import dev.commy.app.wire.Wire
import dev.commy.app.wire.WireException
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.Connection
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.StatusMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Everything coming back out of the core.
 *
 * On Android the return path is libbox's own command server, not the Clash API:
 * an HTTP server inside the tunnel process is memory we do not want and attack
 * surface we do not need, and Clash stays a desktop concern (ADR-0005).
 *
 * libbox wants one `CommandClient` per subscription, so there are four — status,
 * logs, groups, connections — each with its own handler. They also carry the
 * two commands that go the other way, `selectOutbound` and `urlTest`, because
 * both are client calls rather than server ones.
 */
internal class CoreEventBridge(
    private val scope: CoroutineScope,
    private val onCoreLost: (String) -> Unit,
    private val onTraffic: (up: Long, down: Long) -> Unit,
) {

    private val closing = AtomicBoolean(false)
    private val lossReported = AtomicBoolean(false)

    private val clients = mutableListOf<CommandClient>()

    private var statusClient: CommandClient? = null
    private var groupClient: CommandClient? = null

    private val connections = linkedMapOf<String, ConnectionRow>()
    private var connectionsDirty = false
    private var connectionsJob: Job? = null

    @Volatile
    private var lastGroups: List<GroupSnapshot> = emptyList()

    /**
     * Group refreshes, for `urlTest` to wait on.
     *
     * No replay: a url test has to see the update its own request produced, and
     * a cached one from a second ago would answer instantly with a stale number.
     */
    private val groupUpdates = MutableSharedFlow<List<GroupSnapshot>>(
        replay = 0,
        extraBufferCapacity = 4,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    /** The outbound the main group points at, for the notification. */
    val selectedNode: String?
        get() = lastGroups.firstOrNull { it.selected != null }?.selected

    suspend fun start() {
        statusClient = open(Libbox.CommandStatus, StatusHandler())
        open(Libbox.CommandLog, LogHandler())
        groupClient = open(Libbox.CommandGroup, GroupHandler())
        open(Libbox.CommandConnections, ConnectionHandler())
        startConnectionTicker()
    }

    fun close() {
        closing.set(true)
        connectionsJob?.cancel()
        connectionsJob = null
        for (client in clients) {
            runCatching { client.disconnect() }
        }
        clients.clear()
        statusClient = null
        groupClient = null
        synchronized(connections) { connections.clear() }
    }

    /** `getStartedAt`, or null when the core has not told us. */
    fun startedAtMillis(): Long? =
        runCatching { statusClient?.startedAt }.getOrNull()?.takeIf { it > 0 }

    fun proxies(): String = CoreSnapshots.encodeGroups(lastGroups)

    /** Points a group at one of its members, without touching the tunnel. */
    suspend fun select(group: String, tag: String) {
        val client = groupClient ?: throw notRunning()
        withContext(Dispatchers.IO) {
            runCatching { client.selectOutbound(group, tag) }
                .getOrElse { throw WireException.from(Wire.Errors.CONFIG_INVALID, it) }
        }
    }

    /**
     * Measures one outbound, on a libbox API that measures a whole group.
     *
     * `CommandClient.urlTest(groupTag)` takes a group and answers nothing — the
     * numbers arrive later through `writeGroups`. The domain port asks for the
     * delay of a single outbound as a return value, so the asynchrony is hidden
     * here: subscribe, trigger, wait for the next refresh, read one item out.
     *
     * Null means "the probe did not come back", and null is a legitimate answer
     * — a timeout, a missing tag and a delay of zero all mean the same thing to
     * the screen, which draws a dash. Throwing instead would make an
     * unreachable node indistinguishable from a broken app.
     */
    suspend fun urlTest(group: String, tag: String, timeoutMs: Long): Long? {
        val client = groupClient ?: throw notRunning()
        // UNDISPATCHED so the collector is registered before the request goes
        // out. Started lazily, a fast core could answer into an empty room.
        val update = scope.async(start = CoroutineStart.UNDISPATCHED) { groupUpdates.first() }
        try {
            withContext(Dispatchers.IO) { client.urlTest(group) }
        } catch (error: Exception) {
            update.cancel()
            throw WireException.from(Wire.Errors.CONFIG_INVALID, error)
        }
        val groups = withTimeoutOrNull(timeoutMs) { update.await() }
        if (groups == null) {
            update.cancel()
            return null
        }
        val item = groups.firstOrNull { it.tag == group }?.items?.firstOrNull { it.tag == tag }
            ?: groups.flatMap(GroupSnapshot::items).firstOrNull { it.tag == tag }
        val delay = item?.urlTestDelay ?: 0
        return if (delay > 0) delay.toLong() else null
    }

    // ── plumbing ──────────────────────────────────────────────────────────

    private suspend fun open(command: Int, handler: CommandClientAdapter): CommandClient {
        val options = CommandClientOptions().apply {
            addCommand(command)
            // Go durations are nanoseconds. Passing milliseconds here gives a
            // status tick every 16 minutes and a traffic graph that never moves.
            setStatusInterval(STATUS_INTERVAL_NANOS)
        }
        val client = Libbox.newCommandClient(handler, options)
        connect(client)
        clients += client
        return client
    }

    /**
     * Connects, retrying while the command server comes up.
     *
     * The server is started a few instructions earlier on another thread, so
     * the first attempt losing the race is normal rather than exceptional.
     */
    private suspend fun connect(client: CommandClient) {
        var attempt = 0
        while (true) {
            val error = withContext(Dispatchers.IO) {
                runCatching { client.connect() }.exceptionOrNull()
            } ?: return
            attempt++
            if (attempt >= CONNECT_ATTEMPTS) {
                throw WireException.from(Wire.Errors.HELPER_UNAVAILABLE, error)
            }
            delay(CONNECT_RETRY_MS)
        }
    }

    /**
     * Publishes the connection snapshot at most once a second.
     *
     * libbox reports deltas; the snapshot is assembled here because Dart cannot
     * tell a closed connection from a lost event. One hertz is the protocol's
     * ceiling and it is not arbitrary — a busy tunnel produces thousands of
     * events a second, and forwarding them raw floods the channel and stalls
     * the UI on a screen most users never open.
     */
    private fun startConnectionTicker() {
        connectionsJob = scope.launch {
            while (isActive) {
                delay(CONNECTIONS_INTERVAL_MS)
                val snapshot = synchronized(connections) {
                    if (!connectionsDirty) {
                        return@synchronized null
                    }
                    connectionsDirty = false
                    connections.values.toList()
                }
                if (snapshot != null) {
                    TunnelController.emitConnections(CoreSnapshots.encodeConnections(snapshot))
                }
            }
        }
    }

    private fun reportLoss(message: String) {
        if (closing.get() || !lossReported.compareAndSet(false, true)) {
            return
        }
        onCoreLost(message.ifBlank { "the core stopped responding" })
    }

    private fun notRunning() =
        WireException(Wire.Errors.NOT_RUNNING, "the core is not running")

    // ── handlers, all of them on Go threads ───────────────────────────────

    private inner class StatusHandler : CommandClientAdapter() {
        override fun writeStatus(message: StatusMessage) {
            // No event at all when statistics are off. A zero from "not
            // measuring" and a zero from "no traffic" are the same number, and
            // sending the first makes a working tunnel look dead.
            if (!message.trafficAvailable) {
                return
            }
            TunnelController.emitTraffic(
                CoreSnapshots.encodeTraffic(
                    up = message.uplink,
                    down = message.downlink,
                    upTotal = message.uplinkTotal,
                    downTotal = message.downlinkTotal,
                    at = System.currentTimeMillis(),
                ),
            )
            // The same tick drives the speed line on the notification, which is
            // the only readout a user has while the app is closed.
            onTraffic(message.uplink, message.downlink)
        }

        override fun disconnected(message: String?) = reportLoss(message.orEmpty())
    }

    private inner class LogHandler : CommandClientAdapter() {
        override fun writeLogs(messageList: LogIterator) {
            val lines = mutableListOf<Pair<String?, String>>()
            while (messageList.hasNext()) {
                val entry = messageList.next()
                lines += CoreSnapshots.logLevelName(entry.level) to entry.message
            }
            if (lines.isNotEmpty()) {
                TunnelController.emitLogs(CoreSnapshots.encodeLogs(lines))
            }
        }
    }

    private inner class GroupHandler : CommandClientAdapter() {
        override fun writeGroups(message: OutboundGroupIterator) {
            val groups = mutableListOf<GroupSnapshot>()
            while (message.hasNext()) {
                val group = message.next()
                val items = mutableListOf<GroupItemSnapshot>()
                val itemIterator = group.items
                while (itemIterator.hasNext()) {
                    val item = itemIterator.next()
                    items += GroupItemSnapshot(
                        tag = item.tag,
                        type = item.type,
                        // getURLTestDelay(), not `.urlTestDelay`: Kotlin keeps
                        // the leading capitals of a getter that runs them
                        // together, so the synthetic property is `URLTestDelay`
                        // and the obvious spelling does not resolve.
                        urlTestDelay = item.getURLTestDelay(),
                    )
                }
                groups += GroupSnapshot(
                    tag = group.tag,
                    type = group.type,
                    selected = group.selected?.takeIf(String::isNotBlank),
                    selectable = group.selectable,
                    items = items,
                )
            }
            lastGroups = groups
            groupUpdates.tryEmit(groups)
        }
    }

    private inner class ConnectionHandler : CommandClientAdapter() {
        override fun writeConnectionEvents(events: ConnectionEvents) {
            synchronized(connections) {
                if (events.reset) {
                    connections.clear()
                }
                val iterator = events.iterator()
                while (iterator.hasNext()) {
                    val event = iterator.next()
                    // getID(), not `.id` — see the note on getURLTestDelay().
                    val id = event.getID() ?: continue
                    when (event.type.toLong()) {
                        Libbox.ConnectionEventClosed -> connections.remove(id)
                        else -> merge(id, event.connection, event.uplinkDelta, event.downlinkDelta)
                    }
                }
                connectionsDirty = true
            }
        }

        /** Caller holds the `connections` monitor. */
        private fun merge(id: String, source: Connection?, up: Long, down: Long) {
            if (source != null) {
                connections[id] = source.toRow(id)
                return
            }
            // An update with no connection body carries deltas only, and only
            // for a row we were told about earlier. Nothing to fold them into
            // means the event that created it went missing; dropping it is
            // correct, the next full event will bring the row back.
            val existing = connections[id] ?: return
            connections[id] = existing.copy(up = existing.up + up, down = existing.down + down)
        }
    }

    private fun Connection.toRow(id: String): ConnectionRow = ConnectionRow(
        id = id,
        // displayDestination() is the domain when the core resolved one and the
        // address when it did not, which is what the screen wants to show.
        host = runCatching { displayDestination() }.getOrNull().orEmpty(),
        // Without the rule the connections screen answers nothing: "why is this
        // host going direct" is the only question it exists for.
        rule = rule.orEmpty(),
        outbound = outbound.orEmpty(),
        up = uplinkTotal,
        down = downlinkTotal,
        start = createdAt,
        network = network?.takeIf(String::isNotBlank) ?: DEFAULT_NETWORK,
    )

    private companion object {
        /** One second, in nanoseconds, because Go durations are nanoseconds. */
        const val STATUS_INTERVAL_NANOS = 1_000_000_000L

        const val CONNECTIONS_INTERVAL_MS = 1_000L
        const val CONNECT_ATTEMPTS = 20
        const val CONNECT_RETRY_MS = 100L
        const val DEFAULT_NETWORK = "tcp"
    }
}
