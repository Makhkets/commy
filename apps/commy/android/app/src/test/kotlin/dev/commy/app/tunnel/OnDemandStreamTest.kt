package dev.commy.app.tunnel

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The connections stream, opened for a reader and only for one. Open for
 * nobody, it costs a JNI crossing per connection event and a JSON encode of
 * the whole table every second, for as long as the tunnel is up.
 */
class OnDemandStreamTest {

    /** What the bridge was asked to do, in order. */
    private val calls = mutableListOf<String>()

    private var failOpens = 0

    private val stream = OnDemandStream(
        open = {
            calls += "open"
            if (failOpens > 0) {
                failOpens--
                error("the command server is gone")
            }
        },
        close = { calls += "close" },
    )

    private val demand = MutableStateFlow(false)

    /** Runs [body] while the stream follows [demand], then stops following. */
    private fun following(body: suspend () -> Unit) = runBlocking {
        val job = launch(start = CoroutineStart.UNDISPATCHED) { stream.follow(demand) }
        yield()
        body()
        job.cancel()
    }

    private suspend fun want(value: Boolean) {
        demand.value = value
        yield()
    }

    @Test
    fun `nothing is opened while nobody reads`() = following {
        assertEquals(0, calls.count { it == "open" })
    }

    @Test
    fun `a reader opens the stream and its leaving closes it`() = following {
        want(true)
        want(false)

        assertEquals(listOf("close", "open", "close"), calls)
    }

    @Test
    fun `a reader already there when the tunnel comes up gets the stream at once`() {
        demand.value = true

        following {
            assertEquals(listOf("open"), calls)
        }
    }

    @Test
    fun `a stream that ended is opened again while someone reads it`() = following {
        want(true)
        calls.clear()

        stream.reopen()

        assertEquals(listOf("close", "open"), calls)
    }

    @Test
    fun `a stream that ended stays closed when nobody reads it any more`() = following {
        want(true)
        want(false)
        calls.clear()

        stream.reopen()

        assertEquals(emptyList<String>(), calls)
    }

    @Test
    fun `an open that fails does not stop the stream from following its readers`() = following {
        failOpens = 1
        want(true)
        want(false)
        want(true)

        assertEquals(listOf("close", "open", "close", "open"), calls)
    }
}
