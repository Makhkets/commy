package dev.commy.app.tunnel

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import dev.commy.app.MainActivity
import dev.commy.app.R
import dev.commy.app.wire.IntentBus
import dev.commy.app.wire.Wire
import io.nekohasekai.libbox.Libbox

/**
 * The persistent notification, and the only piece of UI this module owns.
 *
 * On Android 8 and later a foreground service without one is killed, so this is
 * not decoration: it is the thing that keeps the tunnel alive. It is also the
 * only place the user can see state and disconnect while the app is closed,
 * which is why the Disconnect action is on it rather than buried in the app.
 */
internal class TunnelNotifications(private val context: Context) {

    private val manager = context.getSystemService(NotificationManager::class.java)

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        // IMPORTANCE_LOW: visible, silent, no heads-up. A tunnel coming up is
        // not worth a sound, and a notification the user learns to swipe at is
        // a notification that gets the service killed.
        val channel = NotificationChannel(
            CHANNEL_TUNNEL,
            context.getString(R.string.notification_channel_tunnel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.notification_channel_tunnel_description)
            setShowBadge(false)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager?.createNotificationChannel(channel)
    }

    /**
     * Builds the ongoing notification.
     *
     * [node] is the outbound the group currently points at. It is the tag the
     * core knows, not a display name: the native side has no access to the
     * user's profile, and the wire protocol carries no name for it.
     */
    fun build(state: String, node: String?, up: Long, down: Long): Notification {
        val text = buildString {
            append(stateText(state))
            if (!node.isNullOrBlank()) {
                append(" · ")
                append(node)
            }
        }
        val builder = NotificationCompat.Builder(context, CHANNEL_TUNNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.app_name))
            .setContentText(text)
            .setColor(ContextCompat.getColor(context, R.color.commy_connected))
            .setColorized(false)
            .setOngoing(true)
            .setShowWhen(false)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openApp())
            .addAction(
                NotificationCompat.Action.Builder(
                    R.drawable.ic_notification,
                    context.getString(R.string.notification_disconnect),
                    disconnect(),
                ).build(),
            )
        if (up > 0 || down > 0) {
            builder.setSubText(
                context.getString(
                    R.string.notification_speed,
                    Libbox.formatBytes(up),
                    Libbox.formatBytes(down),
                ),
            )
        }
        return builder.build()
    }

    /** Refreshes the ongoing notification in place, without restarting the service. */
    fun update(state: String, node: String?, up: Long, down: Long) {
        manager?.notify(ID_TUNNEL, build(state, node, up, down))
    }

    fun cancel() {
        manager?.cancel(ID_TUNNEL)
    }

    /**
     * "Open Commy to connect."
     *
     * Shown when something outside the app asked for a tunnel — a boot, an
     * always-on VPN start — and the native side has no configuration to bring
     * one up with. It never will: the generated core config is a secret and
     * rule R2 keeps it out of native storage, so only the Dart side, holding
     * the encrypted store, can produce one.
     */
    fun promptToOpenApp() {
        ensureChannel()
        val notification = NotificationCompat.Builder(context, CHANNEL_TUNNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.notification_open_title))
            .setContentText(context.getString(R.string.notification_open_text))
            .setAutoCancel(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(openApp(connect = true))
            .build()
        manager?.notify(ID_PROMPT, notification)
    }

    /**
     * Forwards a `PlatformInterface.sendNotification` from the core.
     *
     * Deprecation warnings and the like. Its own channel so the user can mute
     * them without touching the one that keeps the service alive.
     */
    fun fromCore(identifier: String, title: String, body: String, subtitle: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager?.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_CORE,
                    context.getString(R.string.notification_channel_core),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val notification = NotificationCompat.Builder(context, CHANNEL_CORE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setSubText(subtitle)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openApp())
            .build()
        manager?.notify(identifier, ID_CORE, notification)
    }

    private fun stateText(state: String): String = context.getString(
        when (state) {
            Wire.States.STARTING -> R.string.notification_starting
            Wire.States.CONNECTED -> R.string.notification_connected
            Wire.States.STOPPING -> R.string.notification_stopping
            Wire.States.ERROR -> R.string.notification_error
            else -> R.string.notification_idle
        },
    )

    private fun openApp(connect: Boolean = false): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (connect) {
            intent.putExtra(IntentBus.EXTRA_CONNECT, true)
        }
        return PendingIntent.getActivity(context, if (connect) 1 else 0, intent, FLAGS)
    }

    private fun disconnect(): PendingIntent = PendingIntent.getService(
        context,
        2,
        Intent(context, CommyVpnService::class.java).setAction(CommyVpnService.ACTION_STOP),
        FLAGS,
    )

    companion object {
        const val ID_TUNNEL = 1001
        private const val ID_PROMPT = 1002
        private const val ID_CORE = 1003

        private const val CHANNEL_TUNNEL = "commy.tunnel"
        private const val CHANNEL_CORE = "commy.core"

        // FLAG_IMMUTABLE is mandatory from API 31 and harmless before it. A
        // mutable PendingIntent handed to the notification shade is a way for
        // another app to rewrite the intent that stops our tunnel.
        private const val FLAGS =
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    }
}
