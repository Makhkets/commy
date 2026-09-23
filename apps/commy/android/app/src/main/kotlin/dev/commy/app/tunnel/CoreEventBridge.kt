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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

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

    @Volatile
    private var groupClient: CommandClient? = null

    @Volatile
    private var connectionsClient: CommandClient? = null

    /** Streams with a resubscribe in flight, so a burst of ends asks once. */
    private val resubscribing: MutableSet<Int> = ConcurrentHashMap.newKeySet()

    /**
     * Which subscription of each stream is the current one. A client let go
     * of may still report its own end afterwards; only the current one's end
     * is a reason to subscribe again, or the fresh stream would be replaced
     * every time the old one said goodbye.
     */
    private val groupGeneration = AtomicInteger()
    private val connectionsGeneration = AtomicInteger()

    private val connections = linkedMapOf<String, ConnectionRow>()
    private var connectionsDirty = false
    private var connectionsJob: Job? = null

    @Volatile
    private var lastGroups: List<GroupSnapshot> = emptyList()

    /** The most verbose log level passed on, see [CoreSnapshots.logThreshold]. */
    @Volatile
    private var logThreshold = CoreSnapshots.LOG_INFO

    /** When the url test round of each group began, in milliseconds. */
    private val rounds = mutableMapOf<String, Long>()

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

    /**
     * Subscribes to the status stream, which is the one to open before the
     * core starts: libbox serves it in any state, and its end is how a core
     * that died is noticed at all.
     */
    suspend fun start() {
        statusClient = open(Libbox.CommandStatus, StatusHandler())
    }

    /**
     * Subscribes to logs, groups and connections. Only once the service has
     * started.
     *
     * libbox refuses all three while the service is idle, each in its own way
     * (`daemon/started_service.go`, v1.13.16): the log stream opens with
     * `GetDefaultLogLevel`, and groups and connections with `waitForStarted`,
     * and both answer `os.ErrInvalid` unless the service is starting or
     * started. On that error the stream is over, for good and without a word.
     *
     * The log stream was the first to be caught — not one line of the core's
     * reached the screen in a release build. Groups lost the same race on a
     * fast device, and that one cost more: "Check" and "measure all" wait for
     * the group refresh a url test produces, the refresh never came, and every
     * server was reported down — and drawn grey — while traffic flowed through
     * it. Nothing is lost by waiting: the log starts with the lines the core
     * has kept (512, see `CoreSetup`), groups and connections with a full
     * snapshot.
     */
    suspend fun startStreams() {
        open(Libbox.CommandLog, LogHandler())
        groupClient = open(Libbox.CommandGroup, GroupHandler(groupGeneration.incrementAndGet()))
        connectionsClient = open(
            Libbox.CommandConnections,
            ConnectionHandler(connectionsGeneration.incrementAndGet()),
        )
        startConnectionTicker()
    }

    /** Reads the log level out of the config the core is about to run. */
    fun useConfig(config: String) {
        logThreshold = CoreSnapshots.logThreshold(config)
    }

    fun close() {
        closing.set(true)
        connectionsJob?.cancel()
        connectionsJob = null
        val all = synchronized(clients) { clients.toList().also { clients.clear() } }
        for (client in all) {
            runCatching { client.disconnect() }
        }
        statusClient = null
        groupClient = null
        connectionsClient = null
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
     * `CommandClient.urlTest(groupTag)` takes a group and answers nothing. The
     * core then tests *every* member of the group at once, ten at a time, and
     * pushes a group refresh each time one of them finishes
     * (`daemon/started_service.go`, v1.13.16). The domain port asks for the
     * delay of a single outbound as a return value, so the asynchrony is hidden
     * here.
     *
     * It used to take the first refresh after the request and read the tag out
     * of it. The first refresh is whichever server answered first, and the one
     * asked about was usually still in flight — zero, or the number from last
     * time. On the emulator that was "Check" reporting a working tunnel as
     * unreachable, every time, with nine servers answering in the core log.
     * Now a refresh only counts once it carries a delay for [tag] measured at
     * or after this round began.
     *
     * One round per group at a time. "Measure all" asks for every server in
     * turn, and each ask used to start its own round: nine servers, nine
     * rounds, eighty-one probes. An ask that finds a round of the same group
     * already running waits on that one instead.
     *
     * Null means "the probe did not come back", and null is a legitimate answer
     * — a timeout, a missing tag and a failed test (the core deletes the old
     * number rather than keep it) all mean the same thing to the screen, which
     * draws a dash. Throwing instead would make an unreachable node
     * indistinguishable from a broken app.
     */
    suspend fun urlTest(group: String, tag: String, timeoutMs: Long): Long? {
        val client = groupClient ?: throw notRunning()
        val now = System.currentTimeMillis()
        val (round, starts) = synchronized(rounds) {
            val running = rounds[group]?.takeIf { now - it < timeoutMs }
            if (running != null) {
                running to false
            } else {
                rounds[group] = now
                now to true
            }
        }
        // The core stamps a result with Unix seconds, nothing finer.
        val since = round / MILLIS_PER_SECOND
        // UNDISPATCHED so the collector is registered before the request goes
        // out. Started lazily, a fast core could answer into an empty room.
        val update = scope.async(start = CoroutineStart.UNDISPATCHED) {
            groupUpdates.first { freshDelay(it, group, tag, since) != null }
        }
        // A round that was already running may have measured this one before
        // we subscribed.
        freshDelay(lastGroups, group, tag, since)?.let {
            update.cancel()
            return it
        }
        if (starts) {
            try {
                withContext(Dispatchers.IO) { client.urlTest(group) }
            } catch (error: Exception) {
                update.cancel()
                synchronized(rounds) { rounds.remove(group, round) }
                throw WireException.from(Wire.Errors.CONFIG_INVALID, error)
            }
        }
        val groups = withTimeoutOrNull(timeoutMs) { update.await() }
        if (groups == null) {
            update.cancel()
            return null
        }
        return freshDelay(groups, group, tag, since)
    }

    /** [tag]'s delay in [groups], if it was measured at or after [since]. */
    private fun freshDelay(
        groups: List<GroupSnapshot>,
        group: String,
        tag: String,
        since: Long,
    ): Long? {
        val item = groups.firstOrNull { it.tag == group }?.items?.firstOrNull { it.tag == tag }
            ?: groups.flatMap(GroupSnapshot::items).firstOrNull { it.tag == tag }
            ?: return null
        if (item.urlTestDelay <= 0 || item.urlTestTime < since) {
            return null
        }
        return item.urlTestDelay.toLong()
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
        synchronized(clients) { clients += client }
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

    /**
     * Opens a group or connections subscription again after it ended.
     *
     * libbox ends either stream the moment an update finds the service in
     * any state but started — and a reload puts it in another state for the
     * length of the restart. Left alone, the next "Check" after a routing edit
     * would wait on a stream that is gone. So the stream is reopened after a
     * short pause, until it holds or the bridge is closed; while the core is
     * still coming back, the new subscription fails the same way and asks
     * again. One attempt at a time per stream.
     */
    private fun resubscribe(command: Int) {
        if (closing.get() || !resubscribing.add(command)) {
            return
        }
        scope.launch {
            try {
                delay(RESUBSCRIBE_FIRST_MS)
                if (closing.get()) {
                    return@launch
                }
                if (command == Libbox.CommandGroup) {
                    val next = groupGeneration.incrementAndGet()
                    release(groupClient)
                    groupClient = open(Libbox.CommandGroup, GroupHandler(next))
                } else {
                    val next = connectionsGeneration.incrementAndGet()
                    release(connectionsClient)
                    connectionsClient = open(Libbox.CommandConnections, ConnectionHandler(next))
                }
            } catch (error: Exception) {
                // The command server itself is gone; the status stream says
                // so on its own, and there is nothing left to subscribe to.
            } finally {
                resubscribing.remove(command)
            }
        }
    }

    /** Lets go of a client whose stream has ended. */
    private fun release(client: CommandClient?) {
        client ?: return
        runCatching { client.disconnect() }
        synchronized(clients) { clients.remove(client) }
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
            val threshold = logThreshold
            val lines = mutableListOf<Pair<String?, String>>()
            while (messageList.hasNext()) {
                val entry = messageList.next()
                if (entry.level > threshold) {
                    continue
                }
                lines += CoreSnapshots.logLevelName(entry.level) to entry.message
            }
            if (lines.isNotEmpty()) {
                TunnelController.emitLogs(CoreSnapshots.encodeLogs(lines))
            }
        }
    }

    private inner class GroupHandler(private val generation: Int) : CommandClientAdapter() {
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
                        urlTestTime = item.getURLTestTime(),
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

        override fun disconnected(message: String?) {
            if (generation == groupGeneration.get()) {
                resubscribe(Libbox.CommandGroup)
            }
        }
    }

    private inner class ConnectionHandler(private val generation: Int) : CommandClientAdapter() {
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

        override fun disconnected(message: String?) {
            if (generation == connectionsGeneration.get()) {
                resubscribe(Libbox.CommandConnections)
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
        const val MILLIS_PER_SECOND = 1_000L
        const val CONNECT_ATTEMPTS = 20
        const val CONNECT_RETRY_MS = 100L
        const val RESUBSCRIBE_FIRST_MS = 500L
        const val DEFAULT_NETWORK = "tcp"
    }
}
