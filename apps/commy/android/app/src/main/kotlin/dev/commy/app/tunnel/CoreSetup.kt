package dev.commy.app.tunnel

import android.content.Context
import android.util.Log
import dev.commy.app.BuildConfig
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.SetupOptions
import java.io.File
import java.util.Locale

/**
 * `Libbox.setup`, once per process, before anything else touches the core.
 *
 * Calling any other libbox entry point first is undefined: the base paths are
 * package-level state in Go, and the command server, the clients and the core
 * itself all read them.
 */
internal object CoreSetup {

    private const val TAG = "CommyCore"

    /** Cap on the core's in-memory log ring. Ours is in Dart; this is a backstop. */
    private const val LOG_MAX_LINES = 512L

    /** Where `availablePort` starts looking if we ever need a loopback socket. */
    private const val PORT_SEARCH_START = 28_760

    private var configured = false
    private var loopbackFallbackUsed = false

    /**
     * Prepares the core. Idempotent.
     *
     * The command server is left on its default transport, which on Android is
     * a unix socket inside the app's private directory. The port and secret
     * fields exist for the platforms where that is not an option — the Windows
     * service and the macOS helper both have to cross a process boundary the
     * filesystem does not span — and using them here would put a listening TCP
     * socket on loopback, where every other app on the device can reach it. A
     * shared secret would authenticate it, but the socket that cannot be
     * reached at all is the better answer. [fallBackToLoopback] exists for the
     * case where that assumption turns out to be wrong on some device.
     */
    @Synchronized
    fun ensure(context: Context) {
        if (configured) {
            return
        }
        apply(context, loopback = false)
        configured = true
    }

    /**
     * Retries setup with an explicit loopback command server.
     *
     * Called only after `CommandServer.start()` has already failed once. Returns
     * false when we have already tried, so the caller reports the original
     * failure instead of looping.
     */
    @Synchronized
    fun fallBackToLoopback(context: Context): Boolean {
        if (loopbackFallbackUsed) {
            return false
        }
        loopbackFallbackUsed = true
        return runCatching { apply(context, loopback = true) }
            .onFailure { Log.w(TAG, "loopback command server setup failed: ${it.message}") }
            .isSuccess
    }

    private fun apply(context: Context, loopback: Boolean) {
        val base = context.filesDir
        val working = File(base, "core").apply { mkdirs() }
        val temp = context.cacheDir

        val options = SetupOptions().apply {
            setBasePath(base.absolutePath)
            setWorkingPath(working.absolutePath)
            setTempPath(temp.absolutePath)
            // An upstream workaround for Go stack handling on a handful of old
            // devices. Left off: it is not needed on anything we have measured,
            // and it is the first thing to flip if the core dies on API 24-25
            // hardware with no Go stack trace at all.
            setFixAndroidStack(false)
            setLogMaxLines(LOG_MAX_LINES)
            setDebug(BuildConfig.DEBUG)
            if (loopback) {
                setCommandServerListenPort(Libbox.availablePort(PORT_SEARCH_START))
                setCommandServerSecret(Libbox.randomHex(SECRET_BYTES).value)
            }
        }
        Libbox.setup(options)
        Libbox.setLocale(Locale.getDefault().toLanguageTag())

        if (BuildConfig.DEBUG) {
            // A native crash otherwise leaves nothing behind — the Go runtime
            // writes its panic to stderr, which Android drops on the floor.
            // Debug only: the dump is unredacted, and rule R3 governs anything
            // a user can export.
            runCatching { Libbox.redirectStderr(File(temp, "core-stderr.log").absolutePath) }
        }
    }

    /** 16 bytes of hex. libbox has a CSPRNG; we do not need to bring one. */
    private const val SECRET_BYTES = 16
}
