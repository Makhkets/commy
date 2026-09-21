package dev.commy.app.tunnel

import android.net.DnsResolver
import android.net.Network
import android.os.Build
import android.os.CancellationSignal
import android.system.ErrnoException
import android.system.OsConstants
import android.util.Log
import io.nekohasekai.libbox.ExchangeContext
import io.nekohasekai.libbox.LocalDNSTransport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asExecutor
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The system resolver, handed to the core.
 *
 * **Without this class the tunnel comes up and nothing works**, and the reason
 * is not obvious enough to leave to a comment somewhere else.
 *
 * A `{"type": "local"}` DNS server means "ask the operating system". sing-box
 * implements that for Unix by reading `/etc/resolv.conf`
 * (`dns/transport/local/resolv.go`). **Android has no `/etc/resolv.conf`** —
 * name resolution lives behind netd — so the file is missing, Go falls back to
 * its compiled-in default of `127.0.0.1:53` and `[::1]:53`, and every direct
 * query is sent to a port nothing is listening on.
 *
 * That resolver is not a corner of the configuration. `route.default_domain_
 * resolver` points at it, which makes it the resolver that turns the proxy
 * server's own hostname into an address — the one lookup that has to happen
 * before a single byte can leave. A node written as a hostname (which is every
 * node any panel hands out) can then never be dialled, and the failure looks
 * like a tunnel that connects and carries nothing.
 *
 * libbox provides the way out: `PlatformInterface.localDNSTransport()`.
 * Returning a non-null transport replaces the `local` type in the DNS registry
 * with this one before the configuration is parsed (`experimental/libbox/
 * config.go`, `baseContext`), so the core asks Android instead of reading a
 * file that is not there.
 *
 * ## Two paths, because Android grew the API late
 *
 * * **API 29+** — [raw] is true and [exchange] hands the query to
 *   [DnsResolver] as raw DNS wire format. The whole answer comes back intact:
 *   every query type, the TTLs, the rcode.
 * * **API 24–28** — [raw] is false and the core calls [lookup] instead, which
 *   can only answer A and AAAA. That is the platform's own limit, not ours,
 *   and it matches what the core says about it in `experimental/libbox/dns.go`.
 *
 * ## Which network the query goes out on
 *
 * The **underlying** one, never the tunnel. `DnsResolver` binds the query to
 * the [Network] it is given, and giving it none would let Android route the
 * lookup through whatever is default at the time. Our own package is excluded
 * from our own tunnel, so that would usually still be the physical link — but
 * "usually" is not a guarantee worth a resolution loop, and the monitor already
 * knows the honest answer.
 */
internal class AndroidDnsTransport(
    private val monitor: DefaultNetworkMonitor,
) : LocalDNSTransport {

    /**
     * Whether the core may send raw DNS messages.
     *
     * Decided by the platform, not by configuration: [DnsResolver.rawQuery]
     * arrived in Android 10.
     */
    override fun raw(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    /**
     * Answers one raw DNS query.
     *
     * Blocking on purpose. The core calls this from a Go thread that is already
     * waiting on the answer, and `DnsResolver` is callback-based, so the wait
     * happens here rather than being faked with a spare goroutine.
     */
    override fun exchange(ctx: ExchangeContext, message: ByteArray) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Unreachable: raw() said no, so the core calls lookup() instead.
            throw ErrnoException("rawQuery needs Android 10", OsConstants.EOPNOTSUPP)
        }
        val signal = CancellationSignal()
        val done = CountDownLatch(1)
        // Exactly one write to ctx, whoever gets there first. It is a gomobile
        // proxy over a Go object that dies when this method returns, so a late
        // callback touching it after a timeout is a use-after-free with no
        // exception to catch.
        val answered = AtomicBoolean(false)
        // The core cancels the query when its own context expires. Without this
        // the DnsResolver call outlives the exchange and answers into nothing.
        runCatching { ctx.onCancel { signal.cancel() } }

        DnsResolver.getInstance().rawQuery(
            underlyingNetwork(),
            message,
            DnsResolver.FLAG_EMPTY,
            Dispatchers.IO.asExecutor(),
            signal,
            object : DnsResolver.Callback<ByteArray> {
                override fun onAnswer(answer: ByteArray, rcode: Int) {
                    if (!answered.compareAndSet(false, true)) {
                        return
                    }
                    // A non-zero rcode is still an answer — NXDOMAIN is the
                    // resolver doing its job — but the core wants it as a code
                    // rather than as a body it would have to re-parse.
                    if (rcode == RCODE_SUCCESS) {
                        ctx.rawSuccess(answer)
                    } else {
                        ctx.errorCode(rcode)
                    }
                    done.countDown()
                }

                override fun onError(error: DnsResolver.DnsException) {
                    if (!answered.compareAndSet(false, true)) {
                        return
                    }
                    report(ctx, error)
                    done.countDown()
                }
            },
        )
        if (!done.await(QUERY_TIMEOUT_SECONDS, TimeUnit.SECONDS) &&
            answered.compareAndSet(false, true)
        ) {
            signal.cancel()
            throw ErrnoException("the system resolver did not answer", OsConstants.ETIMEDOUT)
        }
    }

    /**
     * Answers one A or AAAA lookup, for the platforms [exchange] cannot serve.
     *
     * [network] here is the core's word for an address family — `ip4` or `ip6`
     * — and not a [Network]. Filtering by it is not optional: handing an A
     * answer back for an AAAA question is a resolver that lies.
     */
    override fun lookup(ctx: ExchangeContext, network: String, domain: String) {
        val name = domain.trimEnd('.')
        if (name.isEmpty()) {
            ctx.errorCode(RCODE_FORMAT_ERROR)
            return
        }
        val link = underlyingNetwork()
        val resolved = runCatching {
            if (link != null) link.getAllByName(name) else InetAddress.getAllByName(name)
        }.getOrElse {
            ctx.errorCode(RCODE_NAME_ERROR)
            return
        }
        val wanted = resolved.filter { address ->
            when (network) {
                NETWORK_V4 -> address is Inet4Address
                NETWORK_V6 -> address is Inet6Address
                else -> true
            }
        }
        val addresses = wanted.mapNotNull { address ->
            // A scope suffix (fe80::1%wlan0) is not an address the core can
            // parse, and a link-local answer is no use to it anyway.
            address.hostAddress?.substringBefore('%')?.takeIf(String::isNotEmpty)
        }
        if (addresses.isEmpty()) {
            // Not an error: a name with no AAAA is a normal answer, and the
            // core reads an empty success as exactly that.
            ctx.success("")
            return
        }
        ctx.success(addresses.joinToString("\n"))
    }

    /**
     * The link the query rides on, or null to let Android decide.
     *
     * Null is the honest answer while there is no default network: pinning the
     * query to one that just went away only turns a retry into a failure.
     */
    private fun underlyingNetwork(): Network? = monitor.defaultNetwork

    private fun report(ctx: ExchangeContext, error: DnsResolver.DnsException) {
        val cause = error.cause
        if (cause is ErrnoException) {
            ctx.errnoCode(cause.errno)
            return
        }
        Log.w(TAG, "system resolver refused a query: ${error.code}")
        ctx.errorCode(RCODE_SERVER_FAILURE)
    }

    private companion object {
        const val TAG = "CommyDns"

        /** The core's names for the two address families. */
        const val NETWORK_V4 = "ip4"
        const val NETWORK_V6 = "ip6"

        const val RCODE_SUCCESS = 0
        const val RCODE_FORMAT_ERROR = 1
        const val RCODE_SERVER_FAILURE = 2
        const val RCODE_NAME_ERROR = 3

        /**
         * Backstop on a callback that never arrives.
         *
         * `DnsResolver` has its own timeouts, so reaching this one means the
         * platform lost the query. The core has a deadline of its own and would
         * give up first in the normal case; this only exists so the Go thread
         * cannot be parked forever.
         */
        const val QUERY_TIMEOUT_SECONDS = 15L
    }
}
