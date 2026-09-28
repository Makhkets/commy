package dev.commy.app.tunnel

/**
 * What sing-box asked for in `openTun`, copied out of Go memory.
 *
 * Every list here is drained from an iterator the core owns, so the values
 * stay valid after the callback returns and a JVM test can build one by hand.
 */
internal data class TunSpec(
    val mtu: Int,
    val inet4Address: List<Prefix>,
    val inet6Address: List<Prefix>,
    val autoRoute: Boolean,
    /** The resolver inside the tunnel; null when the core named none. */
    val dnsServer: String?,
    /** Routes with the exclusions already subtracted — used with [autoRoute]. */
    val inet4RouteRange: List<Prefix>,
    val inet6RouteRange: List<Prefix>,
    /** Routes as configured — used without [autoRoute]. */
    val inet4RouteAddress: List<Prefix>,
    val inet6RouteAddress: List<Prefix>,
    val inet4RouteExclude: List<Prefix>,
    val inet6RouteExclude: List<Prefix>,
    val includePackage: List<String>,
    val excludePackage: List<String>,
    val httpProxy: HttpProxy?,
)

internal data class HttpProxy(
    val host: String,
    val port: Int,
    val bypass: List<String>,
)

/**
 * What goes into `VpnService.Builder`, decided.
 *
 * Every value was computed by sing-box. Nothing is invented: not the routes,
 * not the exclusions, not the package lists. The one thing added is our own
 * package kept off the tunnel, and that is not policy — a client whose own
 * traffic goes through the tunnel it is building cannot fetch the
 * subscription that would fix it.
 *
 * Separate from the builder so the decisions a leak hides in — which routes,
 * which apps — are tested on the JVM rather than on a device (rule R6).
 */
internal data class TunPlan(
    val mtu: Int,
    val addresses: List<Prefix>,
    val dnsServer: String?,
    val routes: List<Prefix>,
    /** Android 13+ only: an exclusion the platform applies itself. */
    val excludedRoutes: List<Prefix>,
    /** Apps let into the tunnel; empty means "every app not in [disallowed]". */
    val allowed: List<String>,
    /** Apps kept out. Empty whenever [allowed] is not: the builder throws on both. */
    val disallowed: List<String>,
    val httpProxy: HttpProxy?,
) {

    companion object {
        const val DEFAULT_V4 = "0.0.0.0"
        const val DEFAULT_V6 = "::"

        /** `Build.VERSION_CODES.Q`: the platform takes an HTTP proxy. */
        private const val API_HTTP_PROXY = 29

        /** `Build.VERSION_CODES.TIRAMISU`: the platform takes an excluded route. */
        private const val API_EXCLUDE_ROUTE = 33

        fun of(spec: TunSpec, self: String, sdkInt: Int): TunPlan {
            val routes: List<Prefix>
            val excluded: List<Prefix>
            if (spec.autoRoute) {
                routes = autoRoutes(spec)
                // Android 13 can express an exclusion directly, which is more
                // precise than the subtracted range and survives a later
                // route being added.
                excluded = if (sdkInt >= API_EXCLUDE_ROUTE) {
                    spec.inet4RouteExclude + spec.inet6RouteExclude
                } else {
                    emptyList()
                }
            } else {
                routes = spec.inet4RouteAddress + spec.inet6RouteAddress
                excluded = emptyList()
            }
            // Allow list and deny list are mutually exclusive in
            // VpnService.Builder — mixing them throws. Which one is in play was
            // decided in the config by commy_config; this only reads the answer.
            val allowed = spec.includePackage.filterNot { it == self }
            // Nothing to exclude with an allow list: leaving our package out of
            // it already keeps it off the tunnel.
            val disallowed = if (allowed.isNotEmpty()) {
                emptyList()
            } else {
                LinkedHashSet(spec.excludePackage).apply { add(self) }.toList()
            }
            return TunPlan(
                mtu = spec.mtu,
                addresses = spec.inet4Address + spec.inet6Address,
                dnsServer = if (spec.autoRoute) spec.dnsServer else null,
                routes = routes,
                excludedRoutes = excluded,
                allowed = allowed,
                disallowed = disallowed,
                httpProxy = spec.httpProxy?.takeIf { sdkInt >= API_HTTP_PROXY },
            )
        }

        /**
         * RouteRange, not RouteAddress. sing-box computes the range with the
         * exclusions already subtracted, which is the whole reason it exists;
         * reaching for 0.0.0.0/0 here undoes every "do not tunnel this" rule
         * the user set, silently. The default route is only for a core that
         * named no range at all, and only for a family it gave an address.
         */
        private fun autoRoutes(spec: TunSpec): List<Prefix> {
            val ranges = spec.inet4RouteRange + spec.inet6RouteRange
            if (ranges.isNotEmpty()) {
                return ranges
            }
            return buildList {
                if (spec.inet4Address.isNotEmpty()) {
                    add(Prefix(DEFAULT_V4, 0))
                }
                if (spec.inet6Address.isNotEmpty()) {
                    add(Prefix(DEFAULT_V6, 0))
                }
            }
        }
    }
}
