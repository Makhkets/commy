package dev.commy.app.tunnel

import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator

/**
 * `CommandClientHandler` with every method defaulted to nothing.
 *
 * The interface has ten methods and one client subscribes to one command, so
 * nine of them are noise at every implementation site. Overriding only what a
 * given subscription actually receives keeps the handlers down to the few lines
 * that matter.
 *
 * **Every method here runs on a Go thread.** Nothing in a subclass may touch
 * the Flutter engine, an `EventSink`, or any Android view: it goes through
 * `TunnelController`'s flows, which are collected on the main looper.
 */
internal abstract class CommandClientAdapter : CommandClientHandler {

    override fun connected() = Unit

    override fun disconnected(message: String?) = Unit

    override fun clearLogs() = Unit

    override fun setDefaultLogLevel(level: Int) = Unit

    override fun writeLogs(messageList: LogIterator) = Unit

    override fun writeStatus(message: StatusMessage) = Unit

    override fun writeGroups(message: OutboundGroupIterator) = Unit

    override fun writeConnectionEvents(events: ConnectionEvents) = Unit

    /**
     * Clash modes are a desktop concept for us.
     *
     * The mobile core runs with the routing the profile describes; there is no
     * global/rule/direct switch in the product, so both mode callbacks are
     * accepted and dropped.
     */
    override fun initializeClashMode(modeList: StringIterator, currentMode: String?) = Unit

    override fun updateClashMode(newMode: String?) = Unit
}
