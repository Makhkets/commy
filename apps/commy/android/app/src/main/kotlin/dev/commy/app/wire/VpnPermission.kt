package dev.commy.app.wire

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import kotlinx.coroutines.CompletableDeferred

/**
 * The system VPN consent dialog, turned into something a coroutine can await.
 *
 * `VpnService.prepare` answers null when consent is already held and an Intent
 * when it is not. The Intent has to be launched from an Activity and the answer
 * comes back through `onActivityResult`, which is why this cannot live in the
 * service.
 *
 * **A refusal must reach the user.** "The user declined and the app said
 * nothing" is M1 acceptance criterion 4, and the way it is met is that every
 * path out of here either succeeds or throws `permission_denied`.
 */
internal class VpnPermission {

    private var activity: Activity? = null
    private var pending: CompletableDeferred<Boolean>? = null

    fun attach(host: Activity) {
        activity = host
    }

    /**
     * Detaches, failing anything still waiting.
     *
     * The activity going away mid-dialog would otherwise leave `start` hanging
     * until its timeout, and the user staring at a spinner.
     */
    fun detach(host: Activity) {
        if (activity !== host) {
            return
        }
        activity = null
        pending?.complete(false)
        pending = null
    }

    /** Throws [WireException] with `permission_denied` when consent is refused. */
    suspend fun ensure(context: Context) {
        val consent = VpnService.prepare(context) ?: return
        val host = activity ?: throw WireException(
            Wire.Errors.PERMISSION_DENIED,
            "the VPN permission is not granted and no window is open to ask for it",
        )
        val gate = CompletableDeferred<Boolean>()
        pending?.complete(false)
        pending = gate
        host.startActivityForResult(consent, REQUEST_VPN)
        if (!gate.await()) {
            throw WireException(
                Wire.Errors.PERMISSION_DENIED,
                "the VPN permission was declined",
            )
        }
    }

    /**
     * Asks for notification permission, and does not wait for the answer.
     *
     * A refusal is survivable: the foreground service still runs, the user just
     * cannot see or stop the tunnel from the shade. Blocking a connection on it
     * would trade a working tunnel for a nicety.
     */
    fun requestNotifications() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        val host = activity ?: return
        if (host.checkSelfPermission(POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        runCatching { host.requestPermissions(arrayOf(POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS) }
    }

    /** Returns true when the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_VPN) {
            return false
        }
        pending?.complete(resultCode == Activity.RESULT_OK)
        pending = null
        return true
    }

    private companion object {
        const val REQUEST_VPN = 0x7101
        const val REQUEST_NOTIFICATIONS = 0x7102
        const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
    }
}
