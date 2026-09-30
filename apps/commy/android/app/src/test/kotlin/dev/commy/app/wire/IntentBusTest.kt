package dev.commy.app.wire

import android.content.Intent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which launches publish the intent that started the activity. */
class IntentBusTest {

    @Test
    fun `a launch from the tile or a link asks for what it carries`() {
        assertTrue(IntentBus.isFreshLaunch(restored = false, flags = Intent.FLAG_ACTIVITY_NEW_TASK))
        assertTrue(IntentBus.isFreshLaunch(restored = false, flags = 0))
    }

    @Test
    fun `a restored activity does not ask again`() {
        assertFalse(IntentBus.isFreshLaunch(restored = true, flags = Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    @Test
    fun `a relaunch from Recents does not ask again`() {
        // What the system hands a new activity when the user reopens a task
        // whose activity Back had finished: the task's first intent, no saved
        // state, and this flag.
        val fromRecents = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY

        assertFalse(IntentBus.isFreshLaunch(restored = false, flags = fromRecents))
    }
}
