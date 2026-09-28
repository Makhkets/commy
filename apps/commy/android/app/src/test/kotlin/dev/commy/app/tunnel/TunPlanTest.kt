package dev.commy.app.tunnel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What goes into `VpnService.Builder`. Each of these is a leak or a dead
 * tunnel when it goes wrong (rule R6), and none of them shows in the UI.
 */
class TunPlanTest {

    private val self = "dev.commy.app"

    private fun spec(
        autoRoute: Boolean = true,
        v4: List<Prefix> = listOf(Prefix("172.19.0.1", 30)),
        v6: List<Prefix> = listOf(Prefix("fdfe:dcba:9876::1", 126)),
        dns: String? = "172.19.0.2",
        v4Ranges: List<Prefix> = emptyList(),
        v6Ranges: List<Prefix> = emptyList(),
        v4Routes: List<Prefix> = emptyList(),
        v6Routes: List<Prefix> = emptyList(),
        v4Excludes: List<Prefix> = emptyList(),
        v6Excludes: List<Prefix> = emptyList(),
        include: List<String> = emptyList(),
        exclude: List<String> = emptyList(),
        proxy: HttpProxy? = null,
    ) = TunSpec(
        mtu = 9000,
        inet4Address = v4,
        inet6Address = v6,
        autoRoute = autoRoute,
        dnsServer = dns,
        inet4RouteRange = v4Ranges,
        inet6RouteRange = v6Ranges,
        inet4RouteAddress = v4Routes,
        inet6RouteAddress = v6Routes,
        inet4RouteExclude = v4Excludes,
        inet6RouteExclude = v6Excludes,
        includePackage = include,
        excludePackage = exclude,
        httpProxy = proxy,
    )

    private fun plan(spec: TunSpec, sdk: Int = 36) = TunPlan.of(spec, self, sdk)

    // ── routes ────────────────────────────────────────────────────────────

    @Test
    fun `the ranges sing-box computed are the routes, with no default route over them`() {
        // What a "do not tunnel 10.0.0.0/8" rule leaves of the IPv4 space.
        val ranges = listOf(Prefix("0.0.0.0", 5), Prefix("8.0.0.0", 7), Prefix("11.0.0.0", 8))

        val plan = plan(spec(v4Ranges = ranges))

        assertEquals(ranges, plan.routes)
        assertFalse(plan.routes.contains(Prefix(TunPlan.DEFAULT_V4, 0)))
    }

    @Test
    fun `without ranges the default route goes in for each family that has an address`() {
        assertEquals(
            listOf(Prefix(TunPlan.DEFAULT_V4, 0), Prefix(TunPlan.DEFAULT_V6, 0)),
            plan(spec()).routes,
        )
        assertEquals(listOf(Prefix(TunPlan.DEFAULT_V4, 0)), plan(spec(v6 = emptyList())).routes)
    }

    @Test
    fun `exclusions go to the platform from Android 13 on, and never before`() {
        val excluded = listOf(Prefix("192.168.0.0", 16))

        assertEquals(excluded, plan(spec(v4Excludes = excluded), sdk = 33).excludedRoutes)
        assertTrue(plan(spec(v4Excludes = excluded), sdk = 32).excludedRoutes.isEmpty())
    }

    @Test
    fun `without auto route only the configured routes go in, and no resolver`() {
        val routes = listOf(Prefix("10.8.0.0", 16))

        val plan = plan(
            spec(
                autoRoute = false,
                v4Routes = routes,
                v4Ranges = listOf(Prefix("1.0.0.0", 8)),
                v4Excludes = listOf(Prefix("192.168.0.0", 16)),
            ),
            sdk = 36,
        )

        assertEquals(routes, plan.routes)
        assertNull(plan.dnsServer)
        assertTrue(plan.excludedRoutes.isEmpty())
    }

    @Test
    fun `the resolver sing-box named goes in with auto route`() {
        assertEquals("172.19.0.2", plan(spec()).dnsServer)
    }

    @Test
    fun `both address families are kept`() {
        assertEquals(
            listOf(Prefix("172.19.0.1", 30), Prefix("fdfe:dcba:9876::1", 126)),
            plan(spec()).addresses,
        )
    }

    // ── apps ──────────────────────────────────────────────────────────────

    @Test
    fun `with no app lists every app is tunnelled except ours`() {
        val plan = plan(spec())

        assertTrue(plan.allowed.isEmpty())
        assertEquals(listOf(self), plan.disallowed)
    }

    @Test
    fun `a deny list keeps its order and gains our package once`() {
        val plan = plan(spec(exclude = listOf("org.bank", self, "org.game", "org.bank")))

        assertEquals(listOf("org.bank", self, "org.game"), plan.disallowed)
        assertTrue(plan.allowed.isEmpty())
    }

    @Test
    fun `an allow list never lets our own package into the tunnel`() {
        val plan = plan(spec(include = listOf("org.browser", self, "org.chat")))

        assertEquals(listOf("org.browser", "org.chat"), plan.allowed)
    }

    @Test
    fun `an allow list comes with no deny list, which the builder would refuse`() {
        val plan = plan(spec(include = listOf("org.browser"), exclude = listOf("org.bank")))

        assertEquals(listOf("org.browser"), plan.allowed)
        assertTrue(plan.disallowed.isEmpty())
    }

    // ── the HTTP proxy ────────────────────────────────────────────────────

    @Test
    fun `the HTTP proxy is handed over from Android 10 on`() {
        val proxy = HttpProxy("127.0.0.1", 2080, listOf("localhost"))

        assertEquals(proxy, plan(spec(proxy = proxy), sdk = 29).httpProxy)
        assertNull(plan(spec(proxy = proxy), sdk = 28).httpProxy)
    }
}
