package dev.commy.app.tunnel

import java.util.concurrent.atomic.AtomicInteger

/**
 * Which start is still wanted.
 *
 * Every request to stop bumps a generation at the moment it is made; a start
 * remembers the generation it was accepted with and gives way if it changed.
 * A stop that came after a start wins, and a newer start cannot revive an
 * older one that a stop already called off.
 *
 * Starts and stops arrive on the main thread and are carried out later under
 * the transition lock, so this is read on both sides of it — atomics, not the
 * lock.
 */
internal class StartLedger {

    /** Starts accepted and not yet finished, from ACTION_START to success or failure. */
    private val inFlight = AtomicInteger(0)

    private val stops = AtomicInteger(0)

    /** A start has been accepted and has not finished yet. */
    val bringingUp: Boolean get() = inFlight.get() > 0

    /**
     * Accepts a start. Returns its generation, which [isCurrent] checks
     * later. Every call is paired with one [finish].
     */
    fun accept(): Int {
        val generation = stops.get()
        inFlight.incrementAndGet()
        return generation
    }

    /** The start accepted by [accept] has finished, whichever way. */
    fun finish() {
        inFlight.decrementAndGet()
    }

    /** A stop was asked for: every start accepted before now gives way. */
    fun stop() {
        stops.incrementAndGet()
    }

    /** No stop has been asked for since the start of [generation] was accepted. */
    fun isCurrent(generation: Int): Boolean = stops.get() == generation
}
