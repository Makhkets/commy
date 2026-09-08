package dev.commy.app.tunnel

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

/**
 * "Connect on boot", to the extent Android and rule R2 allow one.
 *
 * ## Why this only posts a notification
 *
 * It cannot bring the tunnel up. Doing that needs the generated sing-box
 * configuration; that configuration carries every credential the user owns; and
 * rule R2 keeps it in the encrypted store on the Dart side, whose key the user
 * unlocks. At `BOOT_COMPLETED` there is no Flutter engine, and on a device that
 * has not been unlocked since restart there is credential-encrypted storage we
 * cannot read at all.
 *
 * The alternatives were both worse. Caching a decrypted config in native
 * storage so boot could use it would undo R2 for every user in order to save
 * one tap. Starting the Flutter engine headlessly at boot to decrypt it puts
 * the whole app in every user's boot path for a feature most of them never turn
 * on. So the receiver does the honest thing: it tells the user the tunnel is
 * not up and gives them one tap to bring it up.
 *
 * **The leak-free answer is a system setting, not this class.** A user who
 * needs traffic to never escape unproxied wants Android's own always-on VPN
 * with "Block connections without VPN", which the platform enforces from before
 * the first app starts. That is what the leak checklist in
 * docs/09-security-privacy.md asks for, and it is in android/README.md as a
 * manual test.
 *
 * ## Disabled by default
 *
 * The manifest ships this with `android:enabled="false"`, so an install that
 * never turns the feature on has no boot-time cost at all and never asks the
 * user why a proxy client wants to run at startup. [setEnabled] is the switch.
 * The settings screen flips it through the `setStartOnBoot` method of the wire
 * protocol — after every write of the setting, and once at launch — so the
 * stored switch and this component cannot disagree. The component has to
 * exist regardless: the manifest names it, and a missing class there is a
 * build failure, not a runtime one.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // The receiver is exported, because BOOT_COMPLETED cannot be delivered
        // otherwise. Both actions are protected broadcasts, so no other app can
        // send them — but an explicit intent naming this class can still arrive
        // carrying anything, which is why the action is checked rather than
        // assumed. The worst a forged one achieves is a notification.
        val action = intent.action ?: return
        if (action !in HANDLED) {
            return
        }
        // Nothing is read from the intent and nothing is logged: the only
        // interesting thing an attacker could put in one is a string they would
        // like to see in a bug report.
        TunnelNotifications(context.applicationContext).promptToOpenApp()
    }

    companion object {
        private val HANDLED = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            // After an app update the process is killed and the tunnel with it,
            // so a user who asked for auto-start wants the same prompt here.
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )

        /**
         * Turns the receiver on or off for good.
         *
         * `DONT_KILL_APP` because the alternative is Android restarting our own
         * process while the tunnel is up, to apply a setting that does not
         * affect anything currently running.
         */
        fun setEnabled(context: Context, enabled: Boolean) {
            val state = if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            runCatching {
                context.packageManager.setComponentEnabledSetting(
                    ComponentName(context.applicationContext, BootReceiver::class.java),
                    state,
                    PackageManager.DONT_KILL_APP,
                )
            }
        }
    }
}
