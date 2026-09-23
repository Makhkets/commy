package dev.commy.app.wire

import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.onSubscription
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicReference

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
 * ## Delivered once
 *
 * An intent that arrives before the Flutter engine is listening — which is
 * every intent that opens the app — waits in [pending] and goes to the first
 * subscriber, and then it is gone. This used to be a replaying flow instead,
 * and replay is for the life of the process: the process outlives the
 * activity whenever a tunnel is up, so pressing Back and opening the app again
 * handed the new engine the old intent. On the emulator that was a "connect"
 * from the notification, delivered a second time after the user had
 * disconnected — the tunnel came back up on its own — and a tapped link
 * reopened its import sheet every time the app did.
 *
 * Nothing here is logged. A `vless://` URL carries the user's UUID (rule R3),
 * and the debug line that "just shows what came in" is how it ends up in a bug
 * report.
 */
internal object IntentBus {

    /** An event that arrived while nobody was listening. */
    private val pending = AtomicReference<String?>(null)

    private val live = MutableSharedFlow<String>(
        replay = 0,
        extraBufferCapacity = 4,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    val events: Flow<String> =
        live.onSubscription { pending.getAndSet(null)?.let { emit(it) } }

    fun publish(intent: Intent?) {
        val payload = encode(intent ?: return) ?: return
        if (live.subscriptionCount.value > 0 && live.tryEmit(payload)) {
            return
        }
        pending.set(payload)
        // A subscriber that arrived between the check above and the set has
        // already looked at [pending]. Hand the event over now rather than
        // leave it for whichever engine comes next.
        if (live.subscriptionCount.value > 0) {
            pending.getAndSet(null)?.let(live::tryEmit)
        }
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
