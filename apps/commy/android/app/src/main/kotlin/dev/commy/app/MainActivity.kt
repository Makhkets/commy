package dev.commy.app

import android.content.Intent
import dev.commy.app.wire.CommyChannels
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * The single activity, and the only place the platform channels are wired.
 *
 * It owns nothing about the tunnel. Bringing one up, keeping it up and
 * reporting on it all happen in `CommyVpnService` behind `TunnelController`,
 * which outlives this activity — closing the app does not close the tunnel, and
 * reopening it re-attaches to the one already running.
 *
 * What does have to live here is the system VPN consent dialog: `prepare()`
 * hands back an `Intent` that only an Activity can launch, and the answer comes
 * back through `onActivityResult`.
 */
class MainActivity : FlutterActivity() {

    private var channels: CommyChannels? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channels = CommyChannels(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        ).also {
            it.attach(this)
            // The intent that started us: a tapped vless:// link, a config
            // file, or "connect" from the tile. Published now and replayed to
            // Dart whenever it gets round to subscribing.
            it.onIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // launchMode is singleTask, so a second link while the app is open
        // arrives here rather than as a fresh activity.
        setIntent(intent)
        channels?.onIntent(intent)
    }

    @Deprecated("Superseded by the Activity Result API, which FlutterActivity does not expose")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // Ours first, then Flutter's plugins. FlutterActivity extends Activity
        // rather than ComponentActivity, so registerForActivityResult is not
        // available and this override is the supported path.
        if (channels?.onActivityResult(requestCode, resultCode) == true) {
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        channels?.detach(this)
        channels?.dispose()
        channels = null
        super.onDestroy()
    }
}
