package dev.commy.app.tunnel

import dev.commy.app.wire.Wire
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** What a tap on the Quick Settings tile does in each state. */
class TileTapTest {

    @Test
    fun `a tap on Connecting calls the start off`() {
        // The core is not up yet while the tunnel starts.
        assertTrue(tileTapStops(coreUp = false, state = Wire.States.STARTING))
    }

    @Test
    fun `a tap on a connected tunnel stops it`() {
        assertTrue(tileTapStops(coreUp = true, state = Wire.States.CONNECTED))
    }

    @Test
    fun `a tap with the core up stops it whatever the state says`() {
        assertTrue(tileTapStops(coreUp = true, state = Wire.States.ERROR))
    }

    @Test
    fun `a tap with nothing up asks the app to connect`() {
        assertFalse(tileTapStops(coreUp = false, state = Wire.States.IDLE))
        assertFalse(tileTapStops(coreUp = false, state = Wire.States.ERROR))
    }
}
