package dev.commy.app.tunnel

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat
import io.nekohasekai.libbox.CommandServer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Doze, and the reason the tunnel survives it.
 *
 * **This class is acceptance criterion 3 of milestone M1** — "the tunnel
 * survives device sleep and Doze". It survives because nothing is torn down.
 * When the device enters idle the core is told to [CommandServer.pause]; when
 * it leaves, [CommandServer.wake]. The TUN device, the sockets and the service
 * are untouched by both.
 *
 * Restarting the tunnel on the way out of Doze is the obvious implementation
 * and the wrong one, for the same reason it is wrong on a network change: every
 * open connection dies, and the user's morning is a screen full of things that
 * silently failed overnight.
 *
 * ## What pausing actually buys
 *
 * In Doze the platform suspends our network access in windows anyway. A core
 * that keeps its timers running through that spends the battery it was denied
 * the network for — health checks that cannot reach anything, url tests that
 * time out, keepalives written into a socket the kernel is holding. `pause()`
 * stops that clock; `wake()` starts it and lets the core re-evaluate what
 * changed while it was out.
 *
 * ## Why the receiver is registered here and not in the manifest
 *
 * `ACTION_DEVICE_IDLE_MODE_CHANGED` is not delivered to manifest-declared
 * receivers — the platform stopped waking apps for it, which is the point of
 * Doze. It only arrives at a receiver registered by a running process, and the
 * running process we have is the tunnel service. That is exactly the lifetime
 * we want: no tunnel, nothing to pause.
 */
internal class DozeMonitor(
    context: Context,
    private val scope: CoroutineScope,
) {

    private val appContext = context.applicationContext

    private val power = appContext.getSystemService(PowerManager::class.java)

    @Volatile
    private var commandServer: CommandServer? = null

    /**
     * Mirrors what the core has been told, not what the device is doing.
     *
     * The broadcast repeats on maintenance windows, and `pause()` twice with no
     * `wake()` between is not something libbox promises anything about.
     */
    @Volatile
    private var paused = false

    private var receiver: BroadcastReceiver? = null

    /**
     * Starts watching, and syncs the core to the state the device is already in.
     *
     * The initial read matters: a tunnel brought up by the Quick Settings tile
     * on a phone that has been in a pocket all night starts inside Doze, and a
     * monitor that only reacts to changes would leave the core running full
     * speed until the device happens to wake.
     */
    fun attach(server: CommandServer) {
        commandServer = server
        register()
        sync()
    }

    fun close() {
        val watcher = receiver
        receiver = null
        if (watcher != null) {
            runCatching { appContext.unregisterReceiver(watcher) }
        }
        // Deliberately not calling wake() on the way out. The core is being
        // shut down by the caller; waking it first only gives it work to do
        // between here and closeService().
        paused = false
        commandServer = null
    }

    private fun register() {
        if (receiver != null) {
            return
        }
        val watcher = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED) {
                    return
                }
                sync()
            }
        }
        // NOT_EXPORTED: this is a protected system broadcast, so the platform
        // still delivers it, while no other app on the device can forge one.
        val registered = runCatching {
            ContextCompat.registerReceiver(
                appContext,
                watcher,
                IntentFilter(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        }
        if (registered.isFailure) {
            Log.w(TAG, "cannot watch doze: ${registered.exceptionOrNull()?.message}")
            return
        }
        receiver = watcher
    }

    /** Reads the current idle state and moves the core to match it. */
    private fun sync() {
        val idle = power?.isDeviceIdleMode ?: return
        if (idle == paused) {
            return
        }
        // The server is claimed before the mirror moves. Setting `paused` first
        // and then finding no server leaves this class believing it told the
        // core something it never told it, and the next real transition is
        // swallowed as a no-op.
        val server = commandServer ?: return
        paused = idle
        // Off the main looper: this is a call into Go, and onReceive runs on
        // the main thread with a broadcast timeout hanging over it.
        scope.launch(Dispatchers.IO) {
            runCatching {
                if (idle) {
                    server.pause()
                } else {
                    server.wake()
                }
            }.onFailure { Log.w(TAG, "doze transition to idle=$idle failed: ${it.message}") }
        }
    }

    private companion object {
        const val TAG = "CommyDoze"
    }
}
