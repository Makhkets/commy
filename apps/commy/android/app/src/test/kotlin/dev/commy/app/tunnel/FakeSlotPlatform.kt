package dev.commy.app.tunnel

/** An interface of ours, as the fake platform hands it out. Compared by identity. */
internal class Iface(private val name: String) {
    override fun toString(): String = name
}

/**
 * The platform as [TunnelSlot] meets it, down to the quirk that shaped it:
 * the kill switch question is answered only while an interface of ours is up
 * (`getVpnIfOwner` in the platform) — with none, the answer is false whatever
 * the setting says.
 *
 * Every establish, close and release goes into [events], so a test can check
 * the order — "the block was up before the core's interface closed" is the
 * whole point of the class under test.
 */
internal class FakeSlotPlatform : TunnelSlot.Platform<Iface> {

    /** The user's setting: "Always-on VPN" + "Block connections without VPN". */
    var killSwitch = false

    /** False below Android 10, where the question cannot be asked. */
    override var canAskLockdown = true

    /**
     * False once another app holds the VPN permission: establish returns null,
     * and the kill switch question has no owner to answer for any more.
     */
    var permissionHeld = true

    /** Interfaces of ours that are up right now. */
    val open = mutableSetOf<Iface>()

    val events = mutableListOf<String>()

    var asked = 0
        private set

    var released = 0
        private set

    private var cores = 0
    private var blocks = 0

    /** What the core's `openTun` would establish. */
    fun coreInterface(): Iface {
        val core = Iface("core${++cores}")
        open += core
        events += "establish $core"
        return core
    }

    override fun isLockedDown(): Boolean {
        asked++
        return canAskLockdown && permissionHeld && killSwitch && open.isNotEmpty()
    }

    override fun establishBlock(): Iface? {
        if (!permissionHeld) {
            return null
        }
        val block = Iface("block${++blocks}")
        open += block
        events += "establish $block"
        return block
    }

    override fun close(handle: Iface) {
        events += "close $handle"
        check(open.remove(handle)) { "closed $handle, which was not open: a descriptor closed twice" }
    }

    override fun releaseCore() {
        released++
        events += "release core"
    }
}

internal class FakeMarks : TunnelSlot.Marks {
    override var tunnelUp = false
    override var lockdown = false
}
