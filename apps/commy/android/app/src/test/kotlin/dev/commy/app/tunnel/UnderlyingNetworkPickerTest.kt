package dev.commy.app.tunnel

import dev.commy.app.tunnel.UnderlyingNetworkPicker.Grade
import dev.commy.app.tunnel.UnderlyingNetworkPicker.Move
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Which network the core rides on. A wrong pick shows nowhere in the UI: the
 * tunnel says Connected, the server's name is resolved over a network Android
 * itself declined, and nothing gets through.
 */
class UnderlyingNetworkPickerTest {

    /** The platform as a test drives it: what it chose, and what each network is worth. */
    private class FakePlatform : UnderlyingNetworkPicker.Platform<String> {
        var active: String? = null
        val networks = linkedMapOf<String, Grade>()

        override fun active(): String? = active

        override fun all(): List<String> = networks.keys.toList()

        override fun grade(network: String): Grade = networks[network] ?: Grade.UNUSABLE
    }

    private val platform = FakePlatform()

    /** Android 7–11: a listen that hears every matching network. */
    private val legacy = UnderlyingNetworkPicker(platform, platformPicks = false)

    /** Android 12 and later: the best-matching callback. */
    private val modern = UnderlyingNetworkPicker(platform, platformPicks = true)

    // ── below API 31 ──────────────────────────────────────────────────────

    @Test
    fun `a Wi-Fi without internet does not take the core off validated mobile data`() {
        // A café hotspot comes into range. Android stays on cellular and says
        // "Wi-Fi has no internet"; the listen still reports the Wi-Fi.
        platform.networks["cell"] = Grade.VALIDATED
        platform.networks["wifi"] = Grade.UNPROVEN
        platform.active = "cell"

        assertEquals(Move.To("cell"), legacy.onAvailable("wifi", current = "cell"))
    }

    @Test
    fun `when the platform moves off the current network the core follows, though nothing came or went`() {
        // The core is on a Wi-Fi that then fails its internet check. Android
        // moves to cellular and tells the listen only that the Wi-Fi changed.
        platform.networks["cell"] = Grade.VALIDATED
        platform.networks["wifi"] = Grade.UNPROVEN
        platform.active = "cell"

        assertEquals(Move.To("cell"), legacy.onChanged("wifi", current = "wifi"))
    }

    @Test
    fun `a change on another network is a cue to follow the platform too`() {
        // Cellular kept up in the background becomes the default: the change
        // arrives on cellular, not on the Wi-Fi the core is still riding.
        platform.networks["wifi"] = Grade.UNPROVEN
        platform.networks["cell"] = Grade.VALIDATED
        platform.active = "cell"

        assertEquals(Move.To("cell"), legacy.onChanged("cell", current = "wifi"))
    }

    @Test
    fun `the order networks are reported in on registration does not decide`() {
        // Mobile data kept always on: both networks are up and validated, the
        // phone is on Wi-Fi, and a re-registration reports them in whatever
        // order the platform iterates.
        platform.networks["wifi"] = Grade.VALIDATED
        platform.networks["cell"] = Grade.VALIDATED
        platform.active = "wifi"

        legacy.onAvailable("wifi", current = null)
        val last = legacy.onAvailable("cell", current = "wifi")

        assertEquals(Move.To("wifi"), last)
    }

    @Test
    fun `a network that is gone is not picked, even while the platform still lists it`() {
        platform.networks["wifi"] = Grade.VALIDATED
        platform.networks["cell"] = Grade.VALIDATED
        platform.active = "wifi"

        assertEquals(Move.To("cell"), legacy.onLost("wifi", current = "wifi"))
    }

    @Test
    fun `between two defaults a validated network stands in, not the one listed last`() {
        platform.networks["cell"] = Grade.VALIDATED
        platform.networks["portal"] = Grade.UNPROVEN
        platform.active = null

        assertEquals("cell", legacy.seed())
        assertEquals(Move.To("cell"), legacy.onLost("wifi", current = "wifi"))
    }

    @Test
    fun `an unproven network is still taken when it is all there is`() {
        platform.networks["wifi"] = Grade.UNPROVEN
        platform.active = null

        assertEquals(Move.To("wifi"), legacy.onAvailable("wifi", current = null))
    }

    @Test
    fun `a VPN is never picked, even when the platform names it`() {
        platform.networks["tun0"] = Grade.UNUSABLE
        platform.networks["cell"] = Grade.VALIDATED
        platform.active = "tun0"

        assertEquals(Move.To("cell"), legacy.onAvailable("cell", current = null))
        assertEquals("cell", legacy.seed())
    }

    @Test
    fun `with no network left the core is told there is none`() {
        platform.networks["cell"] = Grade.VALIDATED
        platform.active = "cell"

        assertEquals(Move.Nowhere, legacy.onLost("cell", current = "cell"))
    }

    @Test
    fun `seed has nothing to offer when there is no network`() {
        assertNull(legacy.seed())
        assertNull(modern.seed())
    }

    // ── from API 31 ───────────────────────────────────────────────────────

    @Test
    fun `from API 31 the network the callback names is the platform's pick and is taken as it is`() {
        platform.networks["cell"] = Grade.VALIDATED
        platform.active = "cell"

        assertEquals(Move.To("wifi"), modern.onAvailable("wifi", current = "cell"))
    }

    @Test
    fun `from API 31 only a change on the current network is read again`() {
        assertEquals(Move.Stay, modern.onChanged("cell", current = "wifi"))
        assertEquals(Move.To("wifi"), modern.onChanged("wifi", current = "wifi"))
    }

    @Test
    fun `from API 31 losing the current network falls back to the one named before it`() {
        modern.onAvailable("cell", current = null)
        modern.onAvailable("wifi", current = "cell")

        assertEquals(Move.Stay, modern.onLost("eth", current = "wifi"))
        assertEquals(Move.To("cell"), modern.onLost("wifi", current = "wifi"))
        assertEquals(Move.Nowhere, modern.onLost("cell", current = "cell"))
    }

    @Test
    fun `from API 31 what was heard before the monitor stopped is forgotten`() {
        modern.onAvailable("cell", current = null)
        modern.onAvailable("wifi", current = "cell")

        modern.forget()

        assertEquals(Move.Nowhere, modern.onLost("wifi", current = "wifi"))
    }
}
