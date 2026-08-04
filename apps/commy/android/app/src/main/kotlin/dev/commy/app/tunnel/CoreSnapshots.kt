package dev.commy.app.tunnel

import dev.commy.app.wire.Wire
import org.json.JSONArray
import org.json.JSONObject

/**
 * Plain copies of the libbox values that cross the channel.
 *
 * Everything gomobile hands a callback is a proxy over a Go object whose
 * lifetime ends with the callback. Reading a field after the handler returns is
 * a use-after-free with no exception to catch, so every handler copies what it
 * needs into one of these and lets the proxy go.
 */
internal data class GroupSnapshot(
    val tag: String,
    val type: String,
    val selected: String?,
    val selectable: Boolean,
    val items: List<GroupItemSnapshot>,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put(Wire.Keys.TAG, tag)
        put(Wire.Keys.TYPE, type)
        put(Wire.Keys.SELECTED, selected)
        put(Wire.Keys.SELECTABLE, selectable)
        put(Wire.Keys.ITEMS, JSONArray(items.map(GroupItemSnapshot::toJson)))
    }
}

internal data class GroupItemSnapshot(
    val tag: String,
    val type: String?,
    /** Milliseconds. `0` means "never measured", not "instant". */
    val urlTestDelay: Int,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put(Wire.Keys.TAG, tag)
        put(Wire.Keys.TYPE, type)
        put(Wire.Keys.URL_TEST_DELAY, urlTestDelay)
    }
}

/**
 * One row of the `/connections` snapshot.
 *
 * `up` and `down` are cumulative byte counts for the connection, matching
 * `ConnectionInfo.uploadTotal` / `downloadTotal` on the Dart side — not rates.
 */
internal data class ConnectionRow(
    val id: String,
    val host: String,
    val rule: String,
    val outbound: String,
    val up: Long,
    val down: Long,
    val start: Long,
    val network: String,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put(Wire.Keys.ID, id)
        put(Wire.Keys.HOST, host)
        put(Wire.Keys.RULE, rule)
        put(Wire.Keys.OUTBOUND, outbound)
        put(Wire.Keys.UP, up)
        put(Wire.Keys.DOWN, down)
        put(Wire.Keys.START, start)
        put(Wire.Keys.NETWORK, network)
    }
}

internal object CoreSnapshots {

    /** `proxies()` answers an empty array when the core is not running. */
    const val NO_GROUPS = "[]"

    fun encodeGroups(groups: List<GroupSnapshot>): String =
        JSONArray(groups.map(GroupSnapshot::toJson)).toString()

    fun encodeConnections(rows: Collection<ConnectionRow>): String =
        JSONArray(rows.map(ConnectionRow::toJson)).toString()

    /**
     * A `/traffic` tick.
     *
     * Only ever called when `StatusMessage.getTrafficAvailable()` was true: a
     * zero from "statistics are off" and a zero from "no traffic" are the same
     * number, and sending the first one makes a working tunnel look dead.
     */
    fun encodeTraffic(
        up: Long,
        down: Long,
        upTotal: Long,
        downTotal: Long,
        at: Long,
    ): String = JSONObject().apply {
        put(Wire.Keys.UP, up)
        put(Wire.Keys.DOWN, down)
        put(Wire.Keys.UP_TOTAL, upTotal)
        put(Wire.Keys.DOWN_TOTAL, downTotal)
        put(Wire.Keys.AT, at)
    }.toString()

    /**
     * A batch of `/logs` lines.
     *
     * Raw. Redaction is rule R3 and it happens in Dart's `AppLogger`, because
     * this side has no idea which substring is a credential and a regex written
     * here would cut the useful half while leaving the dangerous half
     * (`wire-protocol.md`, "/logs").
     */
    fun encodeLogs(lines: List<Pair<String?, String>>): String = JSONArray(
        lines.map { (level, message) ->
            JSONObject().apply {
                put(Wire.Keys.LEVEL, level)
                put(Wire.Keys.MESSAGE, message)
                put(Wire.Keys.AT, System.currentTimeMillis())
            }
        },
    ).toString()

    /**
     * Maps a `LogEntry.level` onto the names the protocol lists.
     *
     * The numbering is logrus's, which sing-box inherits: panic 0 … trace 6.
     * Level 0 is returned as `null` rather than `panic` on purpose — zero is
     * also what an unset int field holds, and labelling ordinary output as a
     * panic is a worse failure than not labelling it at all. Dart recovers the
     * level from the text itself when the field is absent, which the protocol
     * explicitly allows.
     */
    fun logLevelName(level: Int): String? = when (level) {
        1 -> "fatal"
        2 -> "error"
        3 -> "warn"
        4 -> "info"
        5 -> "debug"
        6 -> "trace"
        else -> null
    }
}
