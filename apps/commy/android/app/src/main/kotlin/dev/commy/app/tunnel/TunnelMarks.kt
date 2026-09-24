package dev.commy.app.tunnel

import android.content.Context

/**
 * Two facts about the tunnel that have to outlive the process.
 *
 * Both are needed at exactly the moments nothing else can answer: after the
 * process died, when the system restarts the service or the app opens again.
 *
 * - [tunnelUp] tells "the tunnel died with the process" from "the user had
 *   disconnected and only the blocking interface was up". Only the first is a
 *   crash to report.
 * - [lockdown] is what the system kill switch said the last time it could be
 *   asked. `VpnService.isLockdownEnabled()` answers only for an app whose VPN is
 *   up at that moment (`getVpnIfOwner` in the platform), so after a process
 *   death it says "no" whatever the setting is. This is the hint that makes it
 *   worth raising the blocking interface and asking again. ADR-0016.
 *
 * Neither is a secret (rule R2): no host, no credential, no configuration.
 * Written with `commit()`, because the case that reads them is the process
 * dying right after the write.
 */
internal class TunnelMarks(context: Context) {

    private val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    var tunnelUp: Boolean
        get() = prefs.getBoolean(KEY_TUNNEL_UP, false)
        set(value) = write(KEY_TUNNEL_UP, value)

    var lockdown: Boolean
        get() = prefs.getBoolean(KEY_LOCKDOWN, false)
        set(value) = write(KEY_LOCKDOWN, value)

    private fun write(key: String, value: Boolean) {
        if (prefs.getBoolean(key, !value) != value) {
            prefs.edit().putBoolean(key, value).commit()
        }
    }

    private companion object {
        const val FILE = "commy.tunnel"
        const val KEY_TUNNEL_UP = "tunnel_up"
        const val KEY_LOCKDOWN = "lockdown_seen"
    }
}
