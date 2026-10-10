package dev.commy.app

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import dev.commy.app.tunnel.AppLanguage
import dev.commy.app.wire.IntentBus
import dev.commy.app.wire.Wire

/**
 * The three entries a long press on the launcher icon offers: Connect, Scan a
 * QR code, Import from the clipboard (M8; Happ, INCY and v2rayNG all have
 * them).
 *
 * Each one only opens the app with an extra that [IntentBus] turns into an
 * event for Dart, the way the Quick Settings tile does: the profile, the
 * scanner and the clipboard all live on the Dart side, and the native side
 * has nothing to start on its own (rule R2 keeps the config out of it).
 *
 * Dynamic rather than declared in `res/xml`: a static shortcut names its
 * target package literally, and the debug build's `.debug` suffix would point
 * it at an app that is not installed. Published again whenever Dart reports
 * the app's language, so the labels follow Appearance → Language like the
 * notification does, and not only the system's.
 */
internal object AppShortcuts {

    private const val ID_CONNECT = "connect"
    private const val ID_SCAN = "scan"
    private const val ID_PASTE = "paste"

    /** Replaces the shortcuts with ones labelled in the app's language. */
    fun publish(context: Context) {
        val strings = AppLanguage.localize(context, AppLanguage.tag(context)).resources
        val shortcuts = listOf(
            shortcut(
                context,
                id = ID_CONNECT,
                label = strings.getString(R.string.shortcut_connect),
                icon = R.drawable.ic_shortcut_connect,
                intent = open(context).putExtra(IntentBus.EXTRA_CONNECT, true),
            ),
            shortcut(
                context,
                id = ID_SCAN,
                label = strings.getString(R.string.shortcut_scan),
                icon = R.drawable.ic_shortcut_scan,
                intent = open(context).putExtra(IntentBus.EXTRA_OPEN, Wire.Intents.SCAN),
            ),
            shortcut(
                context,
                id = ID_PASTE,
                label = strings.getString(R.string.shortcut_paste),
                icon = R.drawable.ic_shortcut_paste,
                intent = open(context).putExtra(IntentBus.EXTRA_OPEN, Wire.Intents.PASTE),
            ),
        )
        ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts)
    }

    private fun open(context: Context): Intent =
        Intent(context, MainActivity::class.java).setAction(Intent.ACTION_MAIN)

    private fun shortcut(
        context: Context,
        id: String,
        label: String,
        icon: Int,
        intent: Intent,
    ): ShortcutInfoCompat =
        ShortcutInfoCompat.Builder(context, id)
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(IconCompat.createWithResource(context, icon))
            .setIntent(intent)
            .build()
}
