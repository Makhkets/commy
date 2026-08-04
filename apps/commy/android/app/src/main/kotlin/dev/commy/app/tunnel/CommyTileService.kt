package dev.commy.app.tunnel

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import dev.commy.app.MainActivity
import dev.commy.app.R
import dev.commy.app.wire.IntentBus
import dev.commy.app.wire.Wire
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Connect and disconnect from the notification shade.
 *
 * ## Why "connect" opens the app instead of just connecting
 *
 * It cannot just connect. Bringing a tunnel up needs the generated sing-box
 * configuration, that configuration carries every credential the user owns, and
 * rule R2 keeps it in the encrypted store on the Dart side — the native process
 * has no copy and is not allowed one. So the tile asks: it launches the app with
 * `EXTRA_CONNECT`, [IntentBus] turns that into a `{"kind":"connect"}` event, and
 * the Dart side — which knows which profile is selected and can decrypt it —
 * decides what to bring up.
 *
 * Disconnecting has no such problem. Stopping needs no secret, so the stop path
 * goes straight to the service and works with the app closed and the device
 * locked. The asymmetry is deliberate: it is always safe to make stopping
 * easier than starting.
 *
 * ## Threading
 *
 * Every [TileService] callback arrives on the main thread and the tile may only
 * be touched from there, which is what the main-confined scope is for. The
 * status flow is collected only between [onStartListening] and
 * [onStopListening] — outside that window the system has told us the tile is
 * not visible, and a collector left running is a subscription kept alive for
 * a UI nobody is looking at.
 */
class CommyTileService : TileService() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var watching: Job? = null

    override fun onStartListening() {
        super.onStartListening()
        // The tile is shown with whatever it looked like last time until this
        // first render, so it happens before anything can await.
        render(TunnelController.state)
        watching?.cancel()
        watching = scope.launch {
            TunnelController.status.collect { render(TunnelController.state) }
        }
    }

    override fun onStopListening() {
        watching?.cancel()
        watching = null
        super.onStopListening()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onClick() {
        super.onClick()
        if (TunnelController.isRunning) {
            disconnect()
        } else {
            askAppToConnect()
        }
    }

    private fun disconnect() {
        // startService, not startForegroundService: the service is already in
        // the foreground, and asking a running service to stop does not need a
        // new foreground promise we would then have to keep.
        runCatching {
            startService(
                Intent(this, CommyVpnService::class.java).setAction(CommyVpnService.ACTION_STOP),
            )
        }
        // Optimistic, and corrected a moment later by the status flow. Waiting
        // for the real transition leaves the tile looking stuck for as long as
        // the core takes to wind down.
        render(Wire.States.STOPPING)
    }

    /**
     * Opens the app with "the user asked to connect" attached.
     *
     * `unlockAndRun` because an activity cannot be started from behind the lock
     * screen: without it the tap does nothing at all on a locked phone, which
     * reads as a broken tile rather than as a security boundary.
     */
    private fun askAppToConnect() {
        val intent = Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(IntentBus.EXTRA_CONNECT, true)
        unlockAndRun {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Android 14 removed the Intent overload; only a PendingIntent
                // is accepted, so the shade can no longer be made to launch an
                // arbitrary intent on our behalf.
                startActivityAndCollapse(
                    PendingIntent.getActivity(
                        this,
                        REQUEST_CONNECT,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        }
    }

    private fun render(state: String) {
        val tile = qsTile ?: return
        tile.state = when (state) {
            Wire.States.CONNECTED -> Tile.STATE_ACTIVE
            // Not STATE_UNAVAILABLE while starting or stopping: unavailable
            // greys the tile out and swallows the tap, and a user who wants to
            // abort a slow connection has nowhere else to press.
            else -> Tile.STATE_INACTIVE
        }
        tile.label = getString(R.string.app_name)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = getString(subtitleFor(state))
        }
        tile.contentDescription = "${getString(R.string.app_name)}: ${getString(subtitleFor(state))}"
        tile.icon = Icon.createWithResource(this, R.drawable.ic_tile)
        runCatching { tile.updateTile() }
    }

    /** Reuses the notification wording: the tile says the same thing in fewer pixels. */
    private fun subtitleFor(state: String): Int = when (state) {
        Wire.States.STARTING -> R.string.notification_starting
        Wire.States.CONNECTED -> R.string.notification_connected
        Wire.States.STOPPING -> R.string.notification_stopping
        Wire.States.ERROR -> R.string.notification_error
        else -> R.string.notification_idle
    }

    private companion object {
        const val REQUEST_CONNECT = 3
    }
}
