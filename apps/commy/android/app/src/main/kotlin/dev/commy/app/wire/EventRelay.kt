package dev.commy.app.wire

import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * Pumps a [Flow] of JSON strings into one Flutter [EventChannel].
 *
 * [scope] must be confined to the main looper. Everything libbox hands us
 * arrives on a Go thread, and calling `EventSink.success` from there takes the
 * Flutter engine down without a usable stack — the single most expensive
 * mistake available on this boundary (`wire-protocol.md`, "Каналы"). Collecting
 * on a main-dispatcher scope is what moves it back.
 *
 * A `StateFlow` source additionally satisfies the `/status` obligation to
 * deliver the current state the instant Dart subscribes: the collector receives
 * the held value before anything new is produced, so a hot restart re-attaching
 * to a live tunnel sees `connected` rather than `idle`.
 */
internal class EventRelay(
    private val scope: CoroutineScope,
    private val source: Flow<String>,
) : EventChannel.StreamHandler {

    private var job: Job? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        // Flutter re-listens after a hot restart without always cancelling
        // first; dropping the old collector here keeps one sink per channel.
        job?.cancel()
        job = scope.launch {
            source.collect(events::success)
        }
    }

    override fun onCancel(arguments: Any?) {
        job?.cancel()
        job = null
    }
}
