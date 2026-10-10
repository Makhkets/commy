package dev.commy.app.tunnel

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import dev.commy.app.MainActivity
import dev.commy.app.R
import dev.commy.app.wire.IntentBus
import dev.commy.app.wire.Wire

/**
 * The home-screen widget: the tunnel's state and one button
 * (docs/19-commy-cloud.md, §3.1 — "the tile, on the home screen").
 *
 * It does what the Quick Settings tile does and for the same reasons
 * ([CommyTileService]): stopping goes straight to the service, because it
 * needs no secret; connecting opens the app with "connect" attached, because
 * the configuration lives encrypted on the Dart side (rule R2) and this
 * process may not hold a copy.
 *
 * Kept current by [TunnelController.watchWidgets], which pushes every state
 * change to the widgets on screen. Nothing runs on a timer: the system does
 * not wake us to redraw, we redraw when something changed.
 */
class CommyWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        TunnelController.watchWidgets(context)
        render(context, manager, ids, TunnelController.state)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            toggle(context)
            return
        }
        super.onReceive(context, intent)
    }

    private fun toggle(context: Context) {
        if (tileTapStops(coreUp = TunnelController.isRunning, state = TunnelController.state)) {
            runCatching {
                context.startService(
                    Intent(context, CommyVpnService::class.java).setAction(CommyVpnService.ACTION_STOP),
                )
            }
            return
        }
        context.startActivity(
            Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(IntentBus.EXTRA_CONNECT, true),
        )
    }

    companion object {
        private const val ACTION_TOGGLE = "dev.commy.app.widget.TOGGLE"

        /** Redraws every Commy widget on screen for [state]. */
        fun refresh(context: Context, state: String) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, CommyWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                render(context, manager, ids, state)
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray, state: String) {
            // In the language chosen in the app, as the tile and the
            // notification are: no Flutter here to ask.
            val strings = AppLanguage.localize(context, AppLanguage.tag(context))
            val connected = state == Wire.States.CONNECTED
            val busy = state == Wire.States.STARTING || state == Wire.States.STOPPING
            val views = RemoteViews(context.packageName, R.layout.widget_commy).apply {
                setTextViewText(R.id.widget_title, strings.getString(R.string.app_name))
                setTextViewText(R.id.widget_status, strings.getString(statusFor(state)))
                setTextViewText(
                    R.id.widget_button,
                    strings.getString(
                        when {
                            busy -> R.string.widget_wait
                            connected -> R.string.widget_disconnect
                            else -> R.string.widget_connect
                        },
                    ),
                )
                setInt(
                    R.id.widget_dot,
                    "setBackgroundResource",
                    if (connected) R.drawable.widget_dot_on else R.drawable.widget_dot_off,
                )
                setInt(
                    R.id.widget_button,
                    "setBackgroundResource",
                    if (connected) R.drawable.widget_button_off else R.drawable.widget_button_on,
                )
                setTextColor(
                    R.id.widget_button,
                    ContextCompat.getColor(
                        context,
                        if (connected) R.color.widget_text else R.color.widget_button_text,
                    ),
                )
                val toggle = PendingIntent.getBroadcast(
                    context,
                    REQUEST_TOGGLE,
                    Intent(context, CommyWidgetProvider::class.java).setAction(ACTION_TOGGLE),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                setOnClickPendingIntent(R.id.widget_button, toggle)
                val open = PendingIntent.getActivity(
                    context,
                    REQUEST_OPEN,
                    Intent(context, MainActivity::class.java)
                        .setAction(Intent.ACTION_MAIN)
                        .addCategory(Intent.CATEGORY_LAUNCHER),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                setOnClickPendingIntent(R.id.widget_root, open)
                setContentDescription(
                    R.id.widget_root,
                    "${strings.getString(R.string.app_name)}: ${strings.getString(statusFor(state))}",
                )
            }
            manager.updateAppWidget(ids, views)
        }

        private fun statusFor(state: String): Int = when (state) {
            Wire.States.STARTING -> R.string.notification_starting
            Wire.States.CONNECTED -> R.string.notification_connected
            Wire.States.STOPPING -> R.string.notification_stopping
            Wire.States.ERROR -> R.string.notification_error
            else -> R.string.notification_idle
        }

        private const val REQUEST_TOGGLE = 41
        private const val REQUEST_OPEN = 42
    }
}
