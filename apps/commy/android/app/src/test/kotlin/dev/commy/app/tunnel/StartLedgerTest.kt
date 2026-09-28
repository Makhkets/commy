package dev.commy.app.tunnel

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** "Disconnect during Connecting…", double taps, and starts queued behind stops. */
class StartLedgerTest {

    private val ledger = StartLedger()

    @Test
    fun `a start nobody stopped is still wanted`() {
        val start = ledger.accept()

        assertTrue(ledger.isCurrent(start))
        assertTrue(ledger.bringingUp)
    }

    @Test
    fun `a stop after the tap calls the start off`() {
        val start = ledger.accept()

        ledger.stop()

        assertFalse(ledger.isCurrent(start))
    }

    @Test
    fun `a start after a stop is not called off by it`() {
        ledger.stop()

        val start = ledger.accept()

        assertTrue(ledger.isCurrent(start))
    }

    @Test
    fun `a newer start cannot revive an older one a stop called off`() {
        val older = ledger.accept()
        ledger.stop()
        val newer = ledger.accept()

        assertFalse(ledger.isCurrent(older))
        assertTrue(ledger.isCurrent(newer))
    }

    @Test
    fun `bringing up lasts until every accepted start has finished`() {
        ledger.accept()
        ledger.accept()

        ledger.finish()
        assertTrue(ledger.bringingUp)

        ledger.finish()
        assertFalse(ledger.bringingUp)
    }

    @Test
    fun `a start called off still counts as bringing up until it finishes`() {
        ledger.accept()
        ledger.stop()

        // settle() and the lockdown watch must keep their hands off the slot
        // until the start behind the lock has given way.
        assertTrue(ledger.bringingUp)
    }
}
