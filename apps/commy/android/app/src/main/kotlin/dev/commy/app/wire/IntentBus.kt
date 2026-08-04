package dev.commy.app.wire

import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import org.json.JSONObject

/**
 * Everything the Android system hands the app that is not a tunnel command.
 *
 * A tapped `vless://` link, a config file opened from a chat, a shared URL, a
 * Quick Settings "connect" — all of them arrive as an `Intent`, all of them
 * belong to Dart, and none of them fits the seven-method tunnel protocol. They
 * go out on `dev.commy.app/intents` instead, with the payload shapes listed in
 * `Wire.Intents`.
 *
 * This is an extension beyond `wire-protocol.md`, and a Dart side that never
 * listens loses nothing but deep links: paste and QR import still work.
 *
 * The buffer replays one event, so a link that opened the app is still there
 * when the Flutter engine finishes starting and subscribes. The cost is that a
 * hot restart re-delivers the last one; imports are expected to be idempotent
 * on the Dart side, which they have to be anyway for a link tapped twice.
 *
 * Nothing here is logged. A `vless://` URL carries the user's UUID (rule R3),
 * and the debug line that "just shows what came in" is how it ends up in a bug
 * report.
 */
internal object IntentBus {

    private val flow = MutableSharedFlow<String>(
        replay = 1,
        extraBufferCapacity = 4,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    val events: Flow<String> = flow.asSharedFlow()

    fun publish(intent: Intent?) {
        val payload = encode(intent ?: return) ?: return
        flow.tryEmit(payload)
    }

    private fun encode(intent: Intent): String? {
        if (intent.getBooleanExtra(EXTRA_CONNECT, false)) {
            return event(Wire.Intents.CONNECT)
        }
        return when (intent.action) {
            Intent.ACTION_VIEW -> {
                val uri = intent.data ?: return null
                val kind = when (uri.scheme?.lowercase()) {
                    // A file has to be read through the content resolver, a
                    // link does not. Dart needs to know which it is holding.
                    "content", "file" -> Wire.Intents.FILE
                    else -> Wire.Intents.LINK
                }
                event(kind) { put(Wire.Keys.URI, uri.toString()) }
            }

            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf(String::isNotBlank)
                if (text != null) {
                    return event(Wire.Intents.TEXT) { put(Wire.Keys.TEXT, text) }
                }
                val stream = intent.getParcelableExtraCompat() ?: return null
                event(Wire.Intents.FILE) { put(Wire.Keys.URI, stream.toString()) }
            }

            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun Intent.getParcelableExtraCompat(): Uri? =
        getParcelableExtra(Intent.EXTRA_STREAM) as? Uri

    private fun event(kind: String, fill: JSONObject.() -> Unit = {}): String =
        JSONObject().apply {
            put(Wire.Keys.KIND, kind)
            fill()
        }.toString()

    /** Set on the intent that opens the app from the tile or a notification. */
    const val EXTRA_CONNECT = "dev.commy.app.extra.CONNECT"
}
