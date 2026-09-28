package dev.commy.app.tunnel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The decisions behind ADR-0016 — what backs the VPN slot after every way
 * down — as the emulator runs of session 19 checked them by hand.
 */
class TunnelSlotTest {

    private val platform = FakeSlotPlatform()
    private val marks = FakeMarks()
    private var now = 1_000_000L
    private val slot = TunnelSlot(platform, marks) { now }

    /** A start carried through to "connected", as `bringUpLocked` does it. */
    private fun connect(): Iface {
        slot.beginStart()
        slot.coreComing()
        val core = platform.coreInterface()
        slot.adopt(core)
        slot.coreUp()
        return core
    }

    /** Where [event] sits in the log; fails if it never happened. */
    private fun at(event: String): Int = platform.events.indexOf(event).also {
        assertTrue("expected \"$event\" in ${platform.events}", it >= 0)
    }

    // ── connecting ────────────────────────────────────────────────────────

    @Test
    fun `a start marks the tunnel up before the core raises its interface`() {
        slot.beginStart()
        slot.coreComing()

        // A process that dies from here on has died with a tunnel up.
        assertTrue(marks.tunnelUp)
        assertFalse(slot.isCoreUp)
    }

    @Test
    fun `the core coming up asks the kill switch while its interface is there to be answered`() {
        platform.killSwitch = true

        connect()

        assertTrue(slot.isCoreUp)
        assertTrue(marks.lockdown)
    }

    @Test
    fun `a start from the block closes the block only after the core's interface is up`() {
        platform.killSwitch = true
        connect()
        slot.tearDown(mayBlock = true, assumeLockdown = false)
        val block = slot.tun!!

        val core = connect()

        assertSame(core, slot.tun)
        assertFalse(slot.blocking)
        assertTrue(at("establish core2") < at("close $block"))
        assertEquals(setOf(core), platform.open)
    }

    @Test
    fun `a reload replaces the core's interface and closes the old one once`() {
        val first = connect()

        val second = platform.coreInterface()
        slot.adopt(second)

        assertSame(second, slot.tun)
        assertEquals(setOf(second), platform.open)
        assertTrue(at("establish $second") < at("close $first"))
    }

    // ── disconnecting ─────────────────────────────────────────────────────

    @Test
    fun `without the kill switch Disconnect hands the network straight back`() {
        connect()

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertFalse(held)
        assertFalse(slot.blocking)
        assertFalse(slot.isCoreUp)
        assertNull(slot.tun)
        assertTrue(platform.open.isEmpty())
        assertEquals(1, platform.released)
        assertFalse(marks.tunnelUp)
        assertFalse(platform.events.any { it.startsWith("establish block") })
        assertEquals(TunnelSlot.Settle.STOP, slot.settle(held, bringingUp = false))
    }

    @Test
    fun `under the kill switch Disconnect leaves the block up with no gap before it`() {
        platform.killSwitch = true
        val core = connect()

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertTrue(held)
        assertTrue(slot.blocking)
        assertFalse(slot.isCoreUp)
        val block = slot.tun!!
        assertEquals(setOf(block), platform.open)
        // The whole point: a moment with no VPN at all lets DNS out in the clear.
        assertTrue(at("establish $block") < at("close $core"))
        assertTrue(marks.lockdown)
        assertFalse(marks.tunnelUp)
        assertEquals(TunnelSlot.Settle.HOLD_BLOCK, slot.settle(held, bringingUp = false))
    }

    @Test
    fun `a second Disconnect while blocking confirms the block and does not rebuild it`() {
        platform.killSwitch = true
        connect()
        slot.tearDown(mayBlock = true, assumeLockdown = false)
        val block = slot.tun
        val events = platform.events.size

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertTrue(held)
        assertSame(block, slot.tun)
        assertEquals(events, platform.events.size)
    }

    @Test
    fun `a Disconnect while blocking after the kill switch went off lets the block go`() {
        platform.killSwitch = true
        connect()
        slot.tearDown(mayBlock = true, assumeLockdown = false)
        platform.killSwitch = false

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertFalse(held)
        assertFalse(slot.blocking)
        assertTrue(platform.open.isEmpty())
        assertFalse(marks.lockdown)
        assertEquals(TunnelSlot.Settle.STOP, slot.settle(held, bringingUp = false))
    }

    @Test
    fun `another VPN taking the slot leaves it empty whatever the kill switch says`() {
        platform.killSwitch = true
        connect()

        val held = slot.tearDown(mayBlock = false, assumeLockdown = true)

        assertFalse(held)
        assertFalse(slot.blocking)
        assertTrue(platform.open.isEmpty())
        assertFalse(platform.events.any { it.startsWith("establish block") })
    }

    @Test
    fun `without the VPN permission there is no block to raise and the slot empties`() {
        platform.killSwitch = true
        connect()
        platform.permissionHeld = false

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertFalse(held)
        assertNull(slot.tun)
        assertTrue(platform.open.isEmpty())
        assertFalse(platform.events.any { it.startsWith("establish block") })
    }

    @Test
    fun `another VPN taking the slot from the block leaves it empty`() {
        blocking()
        // The user left Commy disconnected behind the block and started
        // another VPN: onRevoke tears down with mayBlock = false.
        platform.permissionHeld = false

        val held = slot.tearDown(mayBlock = false, assumeLockdown = false)

        assertFalse(held)
        assertFalse(slot.blocking)
        assertNull(slot.tun)
        assertTrue(platform.open.isEmpty())
        assertEquals(1, platform.events.count { it.startsWith("establish block") })
        assertEquals(TunnelSlot.Settle.STOP, slot.settle(held, bringingUp = false))
    }

    @Test
    fun `below Android 10 a restart neither asks nor raises a block to ask with`() {
        platform.canAskLockdown = false
        platform.killSwitch = true
        marks.tunnelUp = true

        val held = slot.tearDown(mayBlock = true, assumeLockdown = true)

        assertFalse(held)
        assertEquals(0, platform.asked)
        assertFalse(platform.events.any { it.startsWith("establish") })
    }

    @Test
    fun `below Android 10 Disconnect hands the network back whatever the setting`() {
        platform.canAskLockdown = false
        platform.killSwitch = true
        connect()

        val held = slot.tearDown(mayBlock = true, assumeLockdown = true)

        assertFalse(held)
        assertTrue(platform.open.isEmpty())
        assertFalse(platform.events.any { it.startsWith("establish block") })
    }

    @Test
    fun `tearing down an empty slot twice closes nothing twice`() {
        connect()
        slot.tearDown(mayBlock = true, assumeLockdown = false)

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        // FakeSlotPlatform.close throws on a second close of the same descriptor.
        assertFalse(held)
        assertEquals(2, platform.released)
    }

    // ── after the process died ────────────────────────────────────────────

    @Test
    fun `a restart after a tunnel died raises the block first and keeps it under the kill switch`() {
        platform.killSwitch = true
        marks.tunnelUp = true

        val held = slot.tearDown(mayBlock = true, assumeLockdown = true)

        assertTrue(held)
        assertTrue(slot.blocking)
        assertTrue(marks.lockdown)
        assertFalse(marks.tunnelUp)
        assertEquals(1, platform.open.size)
    }

    @Test
    fun `a restart without the kill switch raises the block to ask and takes it straight down`() {
        marks.tunnelUp = true

        val held = slot.tearDown(mayBlock = true, assumeLockdown = true)

        assertFalse(held)
        assertFalse(slot.blocking)
        assertTrue(platform.open.isEmpty())
        assertEquals(listOf("establish block1", "release core", "close block1").sorted(), platform.events.sorted())
        assertFalse(marks.lockdown)
    }

    @Test
    fun `the remembered answer is reason enough to ask again after a process death`() {
        platform.killSwitch = true
        marks.lockdown = true

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertTrue(held)
        assertTrue(slot.blocking)
    }

    @Test
    fun `with no hint and nothing assumed a user without the kill switch pays nothing`() {
        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertFalse(held)
        assertEquals(0, platform.asked)
        assertFalse(platform.events.any { it.startsWith("establish") })
    }

    // ── the watch on a held block ─────────────────────────────────────────

    private fun blocking(): Iface {
        platform.killSwitch = true
        connect()
        slot.tearDown(mayBlock = true, assumeLockdown = false)
        return slot.tun!!
    }

    // ── a start from the block that does not finish ───────────────────────

    @Test
    fun `a start from the block that fails puts a fresh block up before the old one closes`() {
        val old = blocking()
        // Accepted, then failed before the core raised anything: no config,
        // a config the core refused, a command server that would not start.
        slot.beginStart()

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertTrue(held)
        assertTrue(slot.blocking)
        val fresh = slot.tun!!
        assertNotSame(old, fresh)
        assertTrue(at("establish $fresh") < at("close $old"))
        assertEquals(setOf(fresh), platform.open)
        assertEquals(TunnelSlot.Settle.HOLD_BLOCK, slot.settle(held, bringingUp = false))
    }

    @Test
    fun `a start called off after the core's interface came up falls back to the block`() {
        blocking()
        slot.beginStart()
        slot.coreComing()
        val core = platform.coreInterface()
        slot.adopt(core)
        // The stop that won is behind the lock; coreUp() never runs.
        val released = platform.released

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertTrue(held)
        assertTrue(slot.blocking)
        assertFalse(marks.tunnelUp)
        val block = slot.tun!!
        assertTrue(at("establish $block") < at("close $core"))
        assertEquals(setOf(block), platform.open)
        assertEquals(released + 1, platform.released)
        assertEquals(TunnelSlot.Settle.HOLD_BLOCK, slot.settle(held, bringingUp = false))
    }

    @Test
    fun `Disconnect asks the kill switch live rather than trusting an answer from before`() {
        connect()
        // Turned on mid-session; the thirty-second tick has not asked yet.
        platform.killSwitch = true
        assertFalse(marks.lockdown)

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertTrue(held)
        assertTrue(slot.blocking)
        assertTrue(marks.lockdown)
    }

    @Test
    fun `a failed first start under a kill switch turned on mid-start still ends in the block`() {
        // The core's interface came up, the start was then called off, and
        // the kill switch went on in between: the interface is there to ask.
        slot.beginStart()
        slot.coreComing()
        slot.adopt(platform.coreInterface())
        platform.killSwitch = true

        val held = slot.tearDown(mayBlock = true, assumeLockdown = false)

        assertTrue(held)
        assertTrue(slot.blocking)
    }

    @Test
    fun `the watch keeps the block while the kill switch stays on`() {
        val block = blocking()

        assertEquals(false, slot.releaseBlockIfUnlocked(bringingUp = false))
        assertSame(block, slot.tun)
        assertTrue(slot.blocking)
    }

    @Test
    fun `the watch lets the block go once the kill switch is off and the service then stops`() {
        blocking()
        platform.killSwitch = false

        assertEquals(true, slot.releaseBlockIfUnlocked(bringingUp = false))
        assertNull(slot.tun)
        assertFalse(slot.blocking)
        assertTrue(platform.open.isEmpty())
        assertFalse(marks.lockdown)
        assertEquals(TunnelSlot.Settle.STOP, slot.settle(held = false, bringingUp = false))
    }

    @Test
    fun `the watch leaves a block alone once a start is coming for it`() {
        val block = blocking()
        platform.killSwitch = false

        assertNull(slot.releaseBlockIfUnlocked(bringingUp = true))
        assertSame(block, slot.tun)
    }

    @Test
    fun `the watch leaves a running core alone`() {
        connect()

        assertNull(slot.releaseBlockIfUnlocked(bringingUp = false))
        assertEquals(1, platform.open.size)
    }

    @Test
    fun `a watch left over from a block that is already gone does nothing`() {
        blocking()
        platform.killSwitch = false
        // A second Disconnect let the block go; the watch was not told.
        slot.tearDown(mayBlock = true, assumeLockdown = false)
        val asked = platform.asked

        assertNull(slot.releaseBlockIfUnlocked(bringingUp = false))
        assertEquals(asked, platform.asked)
    }

    // ── what the service shows ────────────────────────────────────────────

    @Test
    fun `settle leaves the slot to a start queued behind the teardown`() {
        assertEquals(TunnelSlot.Settle.LEAVE, slot.settle(held = false, bringingUp = true))
        assertEquals(TunnelSlot.Settle.LEAVE, slot.settle(held = true, bringingUp = true))
    }

    @Test
    fun `settle leaves a core that came up in the meantime alone`() {
        connect()

        assertEquals(TunnelSlot.Settle.LEAVE, slot.settle(held = false, bringingUp = false))
    }

    @Test
    fun `settle does not repost a block that already has its notification`() {
        blocking()

        assertEquals(TunnelSlot.Settle.LEAVE, slot.settle(held = false, bringingUp = false))
    }

    // ── always-on starts ──────────────────────────────────────────────────

    @Test
    fun `an always-on start with nothing running stands down`() {
        assertEquals(TunnelSlot.AlwaysOn.STAND_DOWN, slot.alwaysOnStart(bringingUp = false))
    }

    @Test
    fun `an always-on start during a start is the platform repeating itself`() {
        assertEquals(TunnelSlot.AlwaysOn.IGNORE, slot.alwaysOnStart(bringingUp = true))
    }

    @Test
    fun `an always-on start over the block is ignored`() {
        blocking()

        assertEquals(TunnelSlot.AlwaysOn.IGNORE, slot.alwaysOnStart(bringingUp = false))
    }

    @Test
    fun `an always-on start over a running core asks the kill switch again`() {
        connect()

        assertEquals(TunnelSlot.AlwaysOn.IGNORE_AND_RECHECK, slot.alwaysOnStart(bringingUp = false))
    }

    // ── the kill switch answer while connected ────────────────────────────

    @Test
    fun `the traffic tick asks the kill switch at most every thirty seconds`() {
        connect()
        val asked = platform.asked

        slot.rememberLockdown(force = false)
        now += TunnelSlot.LOCKDOWN_REFRESH_MS - 1
        slot.rememberLockdown(force = false)
        assertEquals(asked, platform.asked)

        now += 1
        platform.killSwitch = true
        slot.rememberLockdown(force = false)
        assertEquals(asked + 1, platform.asked)
        assertTrue(marks.lockdown)
    }

    @Test
    fun `a forced check asks every time`() {
        connect()
        val asked = platform.asked

        slot.rememberLockdown(force = true)
        slot.rememberLockdown(force = true)

        assertEquals(asked + 2, platform.asked)
    }

    // ── the service going away ────────────────────────────────────────────

    @Test
    fun `destroy releases the core and closes whatever interface is up`() {
        connect()

        slot.destroy()

        assertTrue(platform.open.isEmpty())
        assertFalse(slot.isCoreUp)
        assertNull(slot.tun)
        assertEquals(1, platform.released)
    }

    @Test
    fun `destroy closes a held block too`() {
        blocking()

        slot.destroy()

        assertTrue(platform.open.isEmpty())
        assertFalse(slot.blocking)
    }
}
