package dev.commy.app.tunnel

/**
 * Which physical network the core rides on, decided from what the platform
 * reports.
 *
 * [DefaultNetworkMonitor] hears the callbacks; this decides what each of them
 * means. It is generic in the network type and imports nothing from
 * `android.*`, so the decision runs on the JVM. `android.net.Network` cannot be
 * built off a device, and a wrong answer here shows nowhere in the UI: the app
 * says Connected and nothing gets through.
 *
 * ## The platform chooses, not the newest callback
 *
 * From API 31 the monitor asks for the best matching network, so the platform
 * does the choosing, and [onAvailable] names the network it picked.
 *
 * Below 31 there is no such request. A plain listen hears about every network
 * that matches, the moment it connects: a Wi-Fi that has not passed the
 * platform's internet check yet, a captive portal, a cellular link kept up in
 * the background. The core used to follow the newest of them. That is how a
 * phone on validated mobile data came to resolve the server's name through a
 * café's sign-in page: Android stayed on cellular, the core moved to the
 * Wi-Fi, and every reconnect failed while the app said Connected. Nothing moved
 * it back either. A Wi-Fi failing validation says so through a capability
 * change, and only the current network's changes were listened to.
 *
 * So below 31 every callback, for any network, is only a cue to ask the
 * platform again which network it chose for this app ([Platform.active]). For
 * Commy that is the physical default and never our own tunnel, because the app
 * keeps its own package out of every TUN it builds.
 */
internal class UnderlyingNetworkPicker<N : Any>(
    private val platform: Platform<N>,
    /** True from API 31, where the callback itself is the platform's pick. */
    private val platformPicks: Boolean,
) {

    /** What the picker asks. `ConnectivityManager` on a device. */
    interface Platform<N : Any> {
        /** The network the platform chose for this app: `activeNetwork`. */
        fun active(): N?

        /** Every network the platform knows about: `allNetworks`. */
        fun all(): List<N>

        /** What [network] is good for right now. */
        fun grade(network: N): Grade
    }

    enum class Grade {
        /** Nothing the core can ride on: no internet, or a VPN, ours included. */
        UNUSABLE,

        /** Claims internet without having shown it: still checking, a portal, a dead uplink. */
        UNPROVEN,

        /** Passed the platform's own internet check. */
        VALIDATED,
    }

    /** What the monitor does after a callback. */
    sealed interface Move<out N> {
        /** Keep the current network and say nothing. */
        data object Stay : Move<Nothing>

        /**
         * Ride on [network]. Read it again even when it is the current one: its
         * interface or its cost may be what changed.
         */
        data class To<N>(val network: N) : Move<N>

        /** There is no network the core can ride on. */
        data object Nowhere : Move<Nothing>
    }

    /**
     * Networks the platform has named, newest last. Only used from API 31.
     *
     * There the platform names one network at a time, and when the current one
     * is lost the one named before it is the fallback until the platform names
     * the next. Guarded by its own monitor because the callbacks arrive on a
     * platform thread and [seed] and [forget] run on ours.
     */
    private val available = LinkedHashSet<N>()

    /** The platform's choice right now, for a monitor that has no answer yet. */
    fun seed(): N? {
        val pick = choose(excluding = null) ?: return null
        if (platformPicks) {
            remember(pick)
        }
        return pick
    }

    fun onAvailable(network: N, current: N?): Move<N> {
        if (!platformPicks) {
            return reconsider(excluding = null)
        }
        remember(network)
        return Move.To(network)
    }

    /** A capability or link-properties change on [network]. */
    fun onChanged(network: N, current: N?): Move<N> {
        if (!platformPicks) {
            return reconsider(excluding = null)
        }
        return if (network == current) Move.To(network) else Move.Stay
    }

    fun onLost(network: N, current: N?): Move<N> {
        if (!platformPicks) {
            // Excluded by hand: the callback runs on our side of an
            // asynchronous hand-off, and the platform may still list the
            // network it has just told us is gone.
            return reconsider(excluding = network)
        }
        val next = synchronized(available) {
            available.remove(network)
            available.lastOrNull()
        }
        if (network != current) {
            return Move.Stay
        }
        return if (next == null) Move.Nowhere else Move.To(next)
    }

    /** Called when the monitor stops listening; what it heard no longer holds. */
    fun forget() {
        synchronized(available) { available.clear() }
    }

    private fun remember(network: N) {
        synchronized(available) {
            // Re-inserted rather than kept in place: "newest last" is the whole
            // ordering, and a set does not reorder on add.
            available.remove(network)
            available.add(network)
        }
    }

    private fun reconsider(excluding: N?): Move<N> {
        val pick = choose(excluding) ?: return Move.Nowhere
        return Move.To(pick)
    }

    /**
     * The network the platform chose, or the best stand-in while it has chosen
     * none.
     *
     * `activeNetwork` is briefly nothing right after a handover. The stand-in
     * is a network that has passed the internet check if there is one: a
     * portal that happens to be listed last is still a portal.
     */
    private fun choose(excluding: N?): N? {
        val active = platform.active()
            ?.takeIf { it != excluding && platform.grade(it) != Grade.UNUSABLE }
        if (active != null) {
            return active
        }
        val usable = platform.all()
            .filter { it != excluding }
            .map { it to platform.grade(it) }
            .filter { (_, grade) -> grade != Grade.UNUSABLE }
        return (usable.lastOrNull { (_, grade) -> grade == Grade.VALIDATED } ?: usable.lastOrNull())
            ?.first
    }
}
