package dev.commy.app.tunnel

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import dev.commy.app.MainActivity
import dev.commy.app.R
import dev.commy.app.wire.IntentBus
import dev.commy.app.wire.Wire

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

    /**
     * What the ongoing notification currently says, or null before it says
     * anything.
     *
     * The traffic stream ticks once a second whether or not anything moved,
     * and [update] hangs off it, so an idle tunnel used to re-post an
     * identical notification sixty times a minute. On a device that is visible
     * — the shade re-lays the row out, and every one of those posts shows up
     * in the system log as a notification being removed and replaced.
     */
    private var posted: String? = null

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
        // Recorded here rather than in [update] so that the notification the
        // service posts with startForeground counts as posted too: otherwise
        // the first traffic tick after a start always repeats it.
        posted = contentKey(state, node, up, down)
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
            .setContentIntent(openAppIntent)
            .addAction(
                NotificationCompat.Action.Builder(
                    R.drawable.ic_notification,
                    context.getString(R.string.notification_disconnect),
                    disconnectIntent,
                ).build(),
            )
        speedText(up, down)?.let(builder::setSubText)
        return builder.build()
    }

    /**
     * Refreshes the ongoing notification in place, and only when it changed.
     *
     * The comparison is on what the user would read, not on the numbers: two
     * different byte counts that format to the same "1.2 MB/s" are the same
     * notification, and a tick that moved nothing is not news.
     */
    fun update(state: String, node: String?, up: Long, down: Long) {
        if (contentKey(state, node, up, down) == posted) {
            return
        }
        manager?.notify(ID_TUNNEL, build(state, node, up, down))
    }

    fun cancel() {
        posted = null
        manager?.cancel(ID_TUNNEL)
    }

    /**
     * The ongoing notification while the blocking interface is held.
     *
     * Says the two things the user needs when the network is gone and Commy
     * is "Disconnected": that the block is the system setting they chose, and
     * that Commy is keeping DNS inside it too — with the two ways out, connect
     * or change the setting.
     */
    fun blocked(): Notification {
        posted = KEY_BLOCKED
        val text = context.getString(R.string.notification_blocked_text)
        return NotificationCompat.Builder(context, CHANNEL_TUNNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.notification_blocked_title))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setOngoing(true)
            .setShowWhen(false)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openAppIntent)
            .addAction(
                NotificationCompat.Action.Builder(
                    R.drawable.ic_notification,
                    context.getString(R.string.notification_connect),
                    openApp(connect = true),
                ).build(),
            )
            .addAction(
                NotificationCompat.Action.Builder(
                    R.drawable.ic_notification,
                    context.getString(R.string.notification_vpn_settings),
                    vpnSettings(),
                ).build(),
            )
            .build()
    }

    /** [blocked] without a foreground service, for when the platform refuses one. */
    fun showBlocked() {
        manager?.notify(ID_TUNNEL, blocked())
    }

    /**
     * Takes down [promptToOpenApp] and [tunnelLost] once a tunnel is up.
     *
     * Both are auto-cancel, which only covers a tap on them. A user who opened
     * the app some other way and connected was left with "Commy is not
     * connected" sitting under "Connected" for as long as the tunnel ran.
     */
    fun clearPrompt() {
        manager?.cancel(ID_PROMPT)
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
        // The alerts channel, silenced: a user who turned on "start on boot"
        // expects to be protected, and in the silent section of the shade,
        // with no icon in the status bar, the one message saying they are not
        // was easy to miss.
        ensureAlertsChannel()
        val notification = NotificationCompat.Builder(context, CHANNEL_ALERTS)
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
     * "The tunnel stopped." Posted when the process died with the tunnel up.
     *
     * Louder than the ongoing notification on purpose — its own channel at
     * default importance, so it reaches the status bar: until the user acts,
     * every app is on the open network. [blocked] is the one exception, the
     * system kill switch ("Block connections without VPN"), and there the
     * truth is the opposite — nothing gets out at all — so the text says
     * that instead. Same id as [promptToOpenApp], because an always-on VPN
     * restarts us at the same moment and two cards saying one thing is noise.
     */
    fun tunnelLost(blocked: Boolean) {
        ensureAlertsChannel()
        val text = context.getString(
            if (blocked) R.string.notification_lost_blocked_text else R.string.notification_lost_text,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.notification_lost_title))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_ERROR)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openApp(connect = true))
            .build()
        manager?.notify(ID_PROMPT, notification)
    }

    /** Default importance: these reach the status bar. */
    private fun ensureAlertsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        manager?.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ALERTS,
                context.getString(R.string.notification_channel_alerts),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = context.getString(R.string.notification_channel_alerts_description)
                setShowBadge(false)
            },
        )
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

    /** Everything the ongoing notification shows, as one comparable string. */
    private fun contentKey(state: String, node: String?, up: Long, down: Long): String =
        "$state|${node.orEmpty()}|${speedText(up, down).orEmpty()}"

    /** The speed line, or null while nothing is moving. */
    private fun speedText(up: Long, down: Long): String? {
        if (up <= 0 && down <= 0) {
            return null
        }
        return context.getString(
            R.string.notification_speed,
            formatBytes(up),
            formatBytes(down),
        )
    }

    /**
     * A byte count the way the app's own screens write it, in the device's
     * language: `1.2 MB` in English, `1,2 МБ` in Russian.
     *
     * `Libbox.formatBytes` did this before and only speaks English, so the
     * Russian notification read `↑ 1.2 MB/с` — a translated suffix on an
     * untranslated number. Mirrors `CommyByteFormat` in commy_ui: binary
     * steps, one decimal below ten.
     */
    private fun formatBytes(value: Long): String {
        val units = context.resources.getStringArray(R.array.byte_units)
        if (value < BYTE_STEP) {
            return "$value ${units.first()}"
        }
        var amount = value.toDouble()
        var unit = 0
        while (amount >= BYTE_STEP && unit < units.lastIndex) {
            amount /= BYTE_STEP
            unit++
        }
        val locale = context.resources.configuration.locales[0]
        val number = String.format(locale, if (amount < 10) "%.1f" else "%.0f", amount)
        return "$number ${units[unit]}"
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

    // Built once each. A PendingIntent is immutable and these two never vary,
    // so rebuilding them on every post was work the system had to de-duplicate
    // for us.
    private val openAppIntent by lazy { openApp(connect = false) }

    private val disconnectIntent by lazy { disconnect() }

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

    private fun vpnSettings(): PendingIntent = PendingIntent.getActivity(
        context,
        3,
        Intent(Settings.ACTION_VPN_SETTINGS).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        FLAGS,
    )

    companion object {
        const val ID_TUNNEL = 1001
        private const val ID_PROMPT = 1002
        private const val ID_CORE = 1003

        private const val KEY_BLOCKED = "blocked"

        private const val CHANNEL_TUNNEL = "commy.tunnel"
        private const val CHANNEL_CORE = "commy.core"
        private const val CHANNEL_ALERTS = "commy.alerts"

        private const val BYTE_STEP = 1024.0

        // FLAG_IMMUTABLE is mandatory from API 31 and harmless before it. A
        // mutable PendingIntent handed to the notification shade is a way for
        // another app to rewrite the intent that stops our tunnel.
        private const val FLAGS =
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    }
}
