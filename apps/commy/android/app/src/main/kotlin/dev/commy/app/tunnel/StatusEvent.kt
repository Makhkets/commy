package dev.commy.app.tunnel

import dev.commy.app.wire.Wire
import org.json.JSONObject

/**
 * One `/status` event.
 *
 * Six states, and the native side only ever produces five of them: `checking`
 * is derived in Dart on top of `connected` from the first url test.
 *
 * [since] is set once, when the tunnel comes up, and carried unchanged through
 * every later event. The on-screen uptime hangs off it, and a value that is
 * recomputed makes the timer jump.
 */
internal data class StatusEvent(
    val state: String,
    val since: Long? = null,
    val reason: String? = null,
    val code: String? = null,
) {

    fun toJson(): String = JSONObject().apply {
        put(Wire.Keys.STATE, state)
        // JSONObject.put(String, Any?) deletes the key when the value is null,
        // which is exactly what we want: the protocol treats an absent optional
        // field as null, so there is nothing to spell out.
        put(Wire.Keys.SINCE, since)
        put(Wire.Keys.REASON, reason)
        put(Wire.Keys.CODE, code)
    }.toString()

    companion object {
        val IDLE = StatusEvent(Wire.States.IDLE)
        val STARTING = StatusEvent(Wire.States.STARTING)
        val STOPPING = StatusEvent(Wire.States.STOPPING)

        fun connected(since: Long): StatusEvent =
            StatusEvent(Wire.States.CONNECTED, since = since)

        /**
         * The tunnel is down because something went wrong.
         *
         * [reason] reaches the user through `CoreCrashedFailure.log` and
         * `ConfigInvalidFailure.detail`, so it carries core diagnostics and
         * never a credential or a config body.
         */
        fun error(code: String, reason: String): StatusEvent =
            StatusEvent(Wire.States.ERROR, reason = reason, code = code)
    }
}
