package dev.commy.app.tunnel

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The wait behind `urlTest`, when the service goes away under it. */
class AwaitWithinTest {

    @Test
    fun `a waiter that answers is passed through`() = runBlocking {
        assertEquals(42, CompletableDeferred(42).awaitWithin(TIMEOUT_MS))
    }

    @Test
    fun `a waiter that never answers is a null after the timeout`() = runBlocking {
        assertNull(CompletableDeferred<Int>().awaitWithin(1))
    }

    @Test
    fun `a waiter whose scope is cancelled is a null, not a silent end`() = runBlocking {
        // The service's scope, which onDestroy cancels.
        val service = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val update = service.async<Int>(start = CoroutineStart.UNDISPATCHED) {
            awaitCancellation()
        }
        val caller = async { update.awaitWithin(TIMEOUT_MS) }
        yield()

        service.cancel()

        assertNull(caller.await())
    }

    @Test
    fun `the caller's own cancellation still ends the call`() = runBlocking {
        val update = CompletableDeferred<Int>()
        var carriedOn = false
        val caller = async {
            update.awaitWithin(TIMEOUT_MS)
            carriedOn = true
        }
        yield()

        caller.cancel()
        caller.join()

        assertTrue(caller.isCancelled)
        assertFalse(carriedOn)
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L
    }
}
