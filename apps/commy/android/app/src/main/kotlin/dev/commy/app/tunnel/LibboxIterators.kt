package dev.commy.app.tunnel

import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator as LibboxNetworkInterfaceIterator
import io.nekohasekai.libbox.RoutePrefix
import io.nekohasekai.libbox.RoutePrefixIterator
import io.nekohasekai.libbox.StringIterator

/**
 * The iterator shapes gomobile generates, and the adapters we need in both
 * directions.
 *
 * gomobile cannot express `List<String>`, so every collection crossing the
 * boundary is an interface with `hasNext`/`next`. Go owns the ones it hands us
 * and they stop being valid the moment the call returns, so they are drained
 * eagerly, never stored.
 */
internal class StringArray(private val values: List<String>) : StringIterator {
    private var index = 0

    override fun hasNext(): Boolean = index < values.size

    override fun len(): Int = values.size

    override fun next(): String = values[index++]

    companion object {
        val EMPTY = StringArray(emptyList())
    }
}

/** Drains a Go-owned string iterator into a Kotlin list. */
internal fun StringIterator?.drain(): List<String> {
    val iterator = this ?: return emptyList()
    val values = mutableListOf<String>()
    while (iterator.hasNext()) {
        values += iterator.next()
    }
    return values
}

/**
 * One `RoutePrefix`, copied out of Go memory.
 *
 * Note the accessor names: `address()`, `prefix()` and `mask()` carry no `get`
 * prefix, unlike almost everything else libbox exposes. Reaching for
 * `getAddress()` here is the usual five minutes lost.
 */
internal data class Prefix(val address: String, val length: Int)

/** Drains a Go-owned route prefix iterator. */
internal fun RoutePrefixIterator?.drain(): List<Prefix> {
    val iterator = this ?: return emptyList()
    val values = mutableListOf<Prefix>()
    while (iterator.hasNext()) {
        val prefix: RoutePrefix = iterator.next()
        values += Prefix(prefix.address(), prefix.prefix())
    }
    return values
}

/** Feeds a prepared list of interfaces back to `PlatformInterface.getInterfaces`. */
internal class InterfaceArray(
    private val values: List<LibboxNetworkInterface>,
) : LibboxNetworkInterfaceIterator {
    private var index = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): LibboxNetworkInterface = values[index++]
}
