package dev.commy.app.tunnel

import android.content.Context
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import io.nekohasekai.mobile.Mobile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicInteger

/**
 * Times the user's servers from the app's own process, tunnel or no tunnel.
 *
 * Two of the three ways the "Ping" setting offers live here; the third, a TCP
 * handshake, needs nothing a Dart socket cannot do.
 *
 * * [outbounds] — a GET through each server, by a core instance of its own
 *   (`core/latency`, bound next to libbox as `core/mobile`). No TUN, no VPN
 *   permission, no service: the servers' outbounds come up, answer, and go.
 * * [echo] — an ICMP echo to the server's address.
 *
 * Both go to the hosts the user entered and to nothing else (rule R1): the
 * probe page of a GET is fetched by the user's server, not by the device. And
 * both leave over the physical network even while the tunnel is up — the app's
 * own package is always excluded from it (`CommyVpnService.applyPackages`).
 */
internal object ServerProbes {

    private val sequence = AtomicInteger()

    /**
     * Measures every outbound of [config] by a GET to [url]; answers the JSON
     * object `{tag: milliseconds}` the core produced, 0 for "no answer".
     *
     * Host names are resolved by the C library, which on Android is netd —
     * this process is outside the tunnel, so that is the physical network's
     * resolver, as for any other app.
     */
    suspend fun outbounds(context: Context, config: String, url: String, timeoutMs: Long): String =
        withContext(Dispatchers.IO) {
            // Same process, same Go runtime as the tunnel's core, and libbox
            // wants its setup before anything else in it runs (CoreSetup).
            CoreSetup.ensure(context)
            Mobile.urlTestOutbounds(config, url, timeoutMs.toInt())
        }

    /**
     * One ICMP echo to [host]: the round trip in milliseconds, or null when
     * nothing came back within [timeoutMs].
     *
     * The name is resolved before the clock starts, as the TCP probe does —
     * a cold lookup is the resolver's cost, not the server's. Null covers
     * everything else that can go wrong, because to the list it is all the
     * same: many servers simply do not answer ICMP.
     */
    suspend fun echo(host: String, timeoutMs: Long): Long? = withContext(Dispatchers.IO) {
        val address = runCatching { InetAddress.getAllByName(host).firstOrNull() }.getOrNull()
            ?: return@withContext null
        runCatching { echoOnce(address, timeoutMs) }.getOrNull()
    }

    /**
     * An unprivileged "ping socket": `SOCK_DGRAM` with `IPPROTO_ICMP`, which
     * Android lets every app open (`ping_group_range` covers all of them).
     * The kernel writes the identifier and the checksum, and hands back only
     * the replies to this socket, without the IP header.
     */
    private fun echoOnce(address: InetAddress, timeoutMs: Long): Long? {
        val v6 = address is Inet6Address
        val socket = Os.socket(
            if (v6) OsConstants.AF_INET6 else OsConstants.AF_INET,
            OsConstants.SOCK_DGRAM,
            if (v6) OsConstants.IPPROTO_ICMPV6 else OsConstants.IPPROTO_ICMP,
        )
        try {
            val number = sequence.incrementAndGet() and 0xFFFF
            val request = ByteArray(ECHO_SIZE).apply {
                this[0] = (if (v6) ICMPV6_ECHO_REQUEST else ICMP_ECHO_REQUEST).toByte()
                this[SEQUENCE_OFFSET] = (number shr 8).toByte()
                this[SEQUENCE_OFFSET + 1] = number.toByte()
            }
            val reply = ByteArray(REPLY_BUFFER)
            val started = System.nanoTime()
            val deadline = started + timeoutMs * NANOS_PER_MILLI
            Os.sendto(socket, request, 0, request.size, 0, address, 0)
            while (true) {
                val left = (deadline - System.nanoTime()) / NANOS_PER_MILLI
                if (left <= 0) {
                    return null
                }
                val wait = StructPollfd().apply {
                    fd = socket
                    events = OsConstants.POLLIN.toShort()
                }
                if (Os.poll(arrayOf(wait), left.toInt()) <= 0) {
                    return null
                }
                val read = Os.recvfrom(socket, reply, 0, reply.size, 0, null)
                val type = if (v6) ICMPV6_ECHO_REPLY else ICMP_ECHO_REPLY
                val answered = ((reply[SEQUENCE_OFFSET].toInt() and 0xFF) shl 8) or
                    (reply[SEQUENCE_OFFSET + 1].toInt() and 0xFF)
                if (read >= HEADER_SIZE && reply[0] == type.toByte() && answered == number) {
                    return ((System.nanoTime() - started) / NANOS_PER_MILLI).coerceAtLeast(1)
                }
                // An error message, or a late reply to an earlier echo: not
                // this one, and the clock is still running.
            }
        } finally {
            Os.close(socket)
        }
    }

    private const val ICMP_ECHO_REQUEST = 8
    private const val ICMP_ECHO_REPLY = 0
    private const val ICMPV6_ECHO_REQUEST = 128
    private const val ICMPV6_ECHO_REPLY = 129

    /** Type, code, checksum, identifier: the sequence number comes next. */
    private const val SEQUENCE_OFFSET = 6
    private const val HEADER_SIZE = 8

    /** The header and 56 bytes, the size `ping` sends. */
    private const val ECHO_SIZE = HEADER_SIZE + 56
    private const val REPLY_BUFFER = 1500
    private const val NANOS_PER_MILLI = 1_000_000L
}
