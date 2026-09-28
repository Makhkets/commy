package dev.commy.app.tunnel

/**
 * What backs the VPN slot: the core's interface, the blocking interface, or
 * nothing — and every decision about moving between the three.
 *
 * Lifted out of [CommyVpnService] so the decisions can be tested without a
 * device. The service keeps what only Android can do (build an interface, ask
 * the kill switch, post a notification, stop itself) behind [Platform]; this
 * class keeps the order those things happen in, which is where every bug of
 * session 19 lived: a blocking interface torn down before the next one was up,
 * a kill switch asked while nothing of ours was up to be answered, a watch that
 * cancelled itself. No `android.*` here on purpose — a JVM test can run it.
 *
 * Mutated only under the service's transition lock, except where noted. The
 * flags are volatile because the service reads them outside it: the main
 * thread deciding what an always-on start means, a traffic tick, `onRevoke`.
 *
 * [H] is the descriptor type — `ParcelFileDescriptor` in the app, anything
 * with identity in a test.
 */
internal class TunnelSlot<H : Any>(
    private val platform: Platform<H>,
    private val marks: Marks,
    private val clock: () -> Long = System::currentTimeMillis,
) {

    /** What only the platform can do. */
    interface Platform<H : Any> {
        /** Whether the platform can answer [isLockedDown] at all (Android 10+). */
        val canAskLockdown: Boolean

        /**
         * Whether the system kill switch is on. Meaningful only while a VPN of
         * ours is up: without one the platform answers false whatever the
         * setting is.
         */
        fun isLockedDown(): Boolean

        /** Raises the blocking interface; null when the permission is gone. */
        fun establishBlock(): H?

        /** Closes one descriptor. Must not throw. */
        fun close(handle: H)

        /** Releases the core, its command server and its watchers — not the descriptor. */
        fun releaseCore()
    }

    /** The two facts that outlive the process; see [TunnelMarks]. */
    interface Marks {
        var tunnelUp: Boolean
        var lockdown: Boolean
    }

    /** What the service should do once a transition has happened. */
    enum class Settle {
        /** Something else owns the slot now, or the block already has its notification. */
        LEAVE,

        /** Show the blocking notification and start watching the kill switch. */
        HOLD_BLOCK,

        /** Take the notification away and stop the service. */
        STOP,
    }

    /** What an always-on start — no configuration, sent by the platform — means now. */
    enum class AlwaysOn {
        /** The slot is ours already; the start is the platform repeating itself. */
        IGNORE,

        /** As [IGNORE], and ask the kill switch again: the user may have just turned it on. */
        IGNORE_AND_RECHECK,

        /** Nothing to run: stand down, into the blocking interface if the kill switch asks. */
        STAND_DOWN,
    }

    /** The descriptor of whatever interface is up: the core's or the block's. */
    @Volatile
    var tun: H? = null
        private set

    /** [tun] is the blocking interface, with no core behind it. */
    @Volatile
    var blocking: Boolean = false
        private set

    @Volatile
    var isCoreUp: Boolean = false
        private set

    /** When the kill switch was last asked about while the core was up. */
    @Volatile
    private var lockdownCheckedAt = 0L

    // ── the core ──────────────────────────────────────────────────────────

    /**
     * A start has the lock and is about to bring the core up.
     *
     * Ends the block without closing it: the core's interface replaces it in
     * [adopt], so there is no moment with no VPN at all.
     */
    fun beginStart() {
        blocking = false
    }

    /**
     * The core is about to raise its interface.
     *
     * Marked before, not after: a process that dies inside the start has died
     * with a tunnel up, and the next start of the process must say so.
     */
    fun coreComing() {
        marks.tunnelUp = true
    }

    /**
     * The core is up and its interface with it — the one moment the platform
     * answers the kill switch question, so it is asked now.
     */
    fun coreUp() {
        isCoreUp = true
        rememberLockdown(force = true)
    }

    /**
     * An interface the core just established. Replaces whatever was up — the
     * previous core interface on a reload, the block on a start — and closes
     * it only now that the new one exists. Called from the core's thread,
     * inside a transition.
     */
    fun adopt(handle: H) {
        tun?.let(platform::close)
        tun = handle
    }

    /**
     * Records what the kill switch says, at most every [LOCKDOWN_REFRESH_MS]
     * unless [force]d: the traffic tick calls this once a second.
     */
    fun rememberLockdown(force: Boolean) {
        val now = clock()
        if (!force && now - lockdownCheckedAt < LOCKDOWN_REFRESH_MS) {
            return
        }
        lockdownCheckedAt = now
        marks.lockdown = platform.isLockedDown()
    }

    // ── taking it down ────────────────────────────────────────────────────

    /**
     * Releases the core and leaves the slot either empty or blocking. Returns
     * whether the blocking interface is up afterwards.
     *
     * The blocking interface is established before the core's is released, so
     * there is no moment with no VPN at all: in that moment Android lets DNS
     * out in the clear. [mayBlock] false — another VPN took the slot — leaves
     * it empty whatever the kill switch says.
     */
    fun tearDown(mayBlock: Boolean, assumeLockdown: Boolean): Boolean {
        if (mayBlock && blocking && !isCoreUp && tun != null) {
            // Already blocking: a second stop only confirms it is still wanted.
            val lockedDown = platform.isLockedDown()
            marks.lockdown = lockedDown
            if (lockedDown) {
                return true
            }
        }
        val block = if (mayBlock) raiseBlockIfLockedDown(assumeLockdown) else null
        val previous = tun
        tun = null
        release()
        if (previous != null && previous !== block) {
            platform.close(previous)
        }
        tun = block
        blocking = block != null
        marks.tunnelUp = false
        return block != null
    }

    /**
     * The blocking interface, if the system kill switch is on; null otherwise.
     *
     * The platform answers "is lockdown on?" only for an app whose VPN is up
     * right now. With our interface up, it is simply asked. Without one — after
     * a process death, from a failed first start, on an always-on start — the
     * block is raised first and the question asked with it up; if the answer
     * is no, it comes straight down. That costs a user without the kill switch
     * one establish-and-close, and only when [Marks.lockdown] or
     * [assumeLockdown] says it is worth asking.
     */
    private fun raiseBlockIfLockedDown(assumeLockdown: Boolean): H? {
        if (!platform.canAskLockdown) {
            return null
        }
        if (tun != null) {
            val lockedDown = platform.isLockedDown()
            marks.lockdown = lockedDown
            return if (lockedDown) platform.establishBlock() else null
        }
        if (!assumeLockdown && !marks.lockdown) {
            return null
        }
        val block = platform.establishBlock() ?: return null
        val lockedDown = platform.isLockedDown()
        marks.lockdown = lockedDown
        if (lockedDown) {
            return block
        }
        platform.close(block)
        return null
    }

    /**
     * One look at the kill switch while blocking: lets the block go once it is
     * off. Null when there is nothing to watch any more — the block is gone or
     * a start owns the slot; false while the kill switch is still on; true
     * when this call released the block.
     *
     * Leaves the service alone: stopping it is [settle]'s answer, on the main
     * thread, after the lock is released.
     */
    fun releaseBlockIfUnlocked(bringingUp: Boolean): Boolean? {
        if (!blocking || isCoreUp || bringingUp) {
            return null
        }
        val lockedDown = platform.isLockedDown()
        marks.lockdown = lockedDown
        if (lockedDown) {
            return false
        }
        blocking = false
        tun?.let(platform::close)
        tun = null
        return true
    }

    /**
     * What the service shows for a transition that has already happened.
     *
     * Checks the state again rather than trusting [held]: a start queued
     * behind the teardown may already own the slot, and it posted its own
     * notification.
     */
    fun settle(held: Boolean, bringingUp: Boolean): Settle = when {
        bringingUp || isCoreUp -> Settle.LEAVE
        held && blocking -> Settle.HOLD_BLOCK
        blocking -> Settle.LEAVE
        else -> Settle.STOP
    }

    /**
     * An always-on start. The platform sends it even while a start is under
     * way ("it's not bound until after establish(), so if it's mid-setup
     * onStartCommand will be sent twice" — Vpn.java), and standing down then
     * would kill the tunnel the user just asked for.
     */
    fun alwaysOnStart(bringingUp: Boolean): AlwaysOn = when {
        isCoreUp -> AlwaysOn.IGNORE_AND_RECHECK
        bringingUp || blocking -> AlwaysOn.IGNORE
        else -> AlwaysOn.STAND_DOWN
    }

    /** The service is being destroyed under us: nothing may outlive it. */
    fun destroy() {
        blocking = false
        release()
    }

    /** Synchronous, idempotent, safe to call twice. */
    private fun release() {
        isCoreUp = false
        platform.releaseCore()
        tun?.let(platform::close)
        tun = null
    }

    companion object {
        /** How long a kill switch answer is trusted while the core is up. */
        const val LOCKDOWN_REFRESH_MS = 30_000L
    }
}
