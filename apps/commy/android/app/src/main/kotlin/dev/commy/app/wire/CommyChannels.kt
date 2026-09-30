package dev.commy.app.wire

import android.app.Activity
import android.content.Context
import android.content.Intent
import dev.commy.app.tunnel.TunnelController
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * All five channels of the wire protocol, plus the intent channel, in one place.
 *
 * Lives for as long as one Flutter engine does. The tunnel does not: it is
 * behind [TunnelController], which is process-wide, so an engine torn down and
 * rebuilt — a hot restart, the user leaving and coming back — re-attaches to a
 * tunnel that never noticed.
 *
 * The scope is confined to the main looper, which is what makes every
 * `Result` and every `EventSink.success` land on the right thread.
 */
internal class CommyChannels(
    context: Context,
    messenger: BinaryMessenger,
) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val resolver = context.applicationContext.contentResolver

    private val permission = VpnPermission()

    private val method = MethodChannel(messenger, Wire.Channels.METHOD).apply {
        setMethodCallHandler(
            CoreMethodHandler(
                context = context.applicationContext,
                scope = scope,
                permission = permission,
            ),
        )
    }

    private val streams = listOf(
        stream(messenger, Wire.Channels.STATUS, TunnelController.status),
        stream(messenger, Wire.Channels.TRAFFIC, TunnelController.traffic),
        stream(messenger, Wire.Channels.LOGS, TunnelController.logs),
        stream(messenger, Wire.Channels.CONNECTIONS, TunnelController.connections),
        stream(messenger, Wire.Channels.INTENTS, IntentBus.events),
    )

    fun attach(activity: Activity) {
        permission.attach(activity)
    }

    fun detach(activity: Activity) {
        permission.detach(activity)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean =
        permission.onActivityResult(requestCode, resultCode)

    /**
     * Hands an intent to Dart, reading the file first when it carries one.
     *
     * Read now, while this activity — and with it the read grant that came
     * with the intent — is alive, and off the main thread, since a provider
     * may take its time. See [FileIntentReader] for why Dart gets the text
     * rather than the address.
     */
    fun onIntent(intent: Intent?) {
        val file = intent?.let(IntentBus::fileOf)
        if (file == null) {
            IntentBus.publish(intent)
            return
        }
        scope.launch {
            val text = withContext(Dispatchers.IO) {
                FileIntentReader.read { resolver.openInputStream(file) }
            }
            if (text == null) {
                IntentBus.publishUnreadableFile()
            } else {
                IntentBus.publishText(text)
            }
        }
    }

    fun dispose() {
        method.setMethodCallHandler(null)
        for (channel in streams) {
            channel.setStreamHandler(null)
        }
        scope.cancel()
    }

    private fun stream(
        messenger: BinaryMessenger,
        name: String,
        source: Flow<String>,
    ): EventChannel = EventChannel(messenger, name).apply {
        setStreamHandler(EventRelay(scope, source))
    }
}
