package dev.commy.app.tunnel

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * A core subscription held open while someone reads it, and only then.
 *
 * Made for the connections stream, the expensive one. While it is open,
 * libbox builds an event for every connection opened or closed and a traffic
 * update for every live connection each second. Each one crosses JNI, and the
 * bridge encodes the whole table to JSON once a second. It used to be open for
 * as long as the tunnel was up, and nearly all of that work went to nobody:
 * the only reader is the Connections tab, and the event stream drops whatever
 * it is handed while no one collects. Now the stream opens when the tab starts
 * listening and closes when it stops, which also gives the tab libbox's full
 * snapshot within a second of opening instead of nothing until the next change.
 *
 * Free of libbox so the rule runs on the JVM. [open] and [close] belong to the
 * bridge; nothing here knows what a command client is.
 */
internal class OnDemandStream(
    private val open: suspend () -> Unit,
    private val close: () -> Unit,
) {

    /**
     * Held across every open and close, so a reopen after the stream ended
     * cannot interleave with the reader leaving and bring back a stream nobody
     * wants.
     */
    private val lock = Mutex()

    private var wanted = false

    /**
     * Opens and closes the stream as [demand] says, until the calling
     * coroutine is cancelled.
     */
    suspend fun follow(demand: Flow<Boolean>) {
        demand.distinctUntilChanged().collect { want ->
            lock.withLock {
                wanted = want
                if (want) {
                    openQuietly()
                } else {
                    close()
                }
            }
        }
    }

    /**
     * Opens the stream again after it ended on its own, which a live reload
     * does, and only if someone still reads it.
     */
    suspend fun reopen() {
        lock.withLock {
            if (!wanted) {
                return
            }
            close()
            openQuietly()
        }
    }

    private suspend fun openQuietly() {
        try {
            open()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            // The command server itself is gone. The status stream reports
            // that on its own, and the next reader to arrive tries again.
        }
    }
}
