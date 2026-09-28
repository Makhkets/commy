package dev.commy.app.tunnel

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The JSON that crosses the channel, checked by the literal field names the
 * Dart side reads (packages/commy_core/docs/wire-protocol.md) — not by the
 * `Wire.Keys` constants, which is where a typo would be.
 */
class CoreSnapshotsTest {

    /** `keys()`, not `keySet()`: the test compiles against Android's org.json, which has only the first. */
    private fun JSONObject.fieldNames(): Set<String> = keys().asSequence().toSet()

    // ── /status ───────────────────────────────────────────────────────────

    @Test
    fun `a status event leaves out what it does not know`() {
        val json = JSONObject(StatusEvent.IDLE.toJson())

        assertEquals("idle", json.getString("state"))
        assertEquals(setOf("state"), json.fieldNames())
    }

    @Test
    fun `connected carries the moment the tunnel came up`() {
        val json = JSONObject(StatusEvent.connected(1_727_000_000_000).toJson())

        assertEquals("connected", json.getString("state"))
        assertEquals(1_727_000_000_000, json.getLong("since"))
    }

    @Test
    fun `an error carries its code and its reason`() {
        val json = JSONObject(StatusEvent.error("core_crashed", "the core stopped").toJson())

        assertEquals("error", json.getString("state"))
        assertEquals("core_crashed", json.getString("code"))
        assertEquals("the core stopped", json.getString("reason"))
        assertFalse(json.has("since"))
    }

    // ── proxies() ─────────────────────────────────────────────────────────

    @Test
    fun `groups carry what the node list draws`() {
        val groups = listOf(
            GroupSnapshot(
                tag = "select",
                type = "selector",
                selected = "Finland",
                selectable = true,
                items = listOf(GroupItemSnapshot("Finland", "vless", 124, urlTestTime = 99)),
            ),
        )

        val group = JSONArray(CoreSnapshots.encodeGroups(groups)).getJSONObject(0)

        assertEquals("select", group.getString("tag"))
        assertEquals("selector", group.getString("type"))
        assertEquals("Finland", group.getString("selected"))
        assertTrue(group.getBoolean("selectable"))
        val item = group.getJSONArray("items").getJSONObject(0)
        assertEquals("Finland", item.getString("tag"))
        assertEquals("vless", item.getString("type"))
        assertEquals(124, item.getInt("urlTestDelay"))
        // Native only: the protocol has no use for when it was measured.
        assertFalse(item.has("urlTestTime"))
    }

    @Test
    fun `a group with nothing selected has no selected field`() {
        val groups = listOf(GroupSnapshot("auto", "urltest", null, false, emptyList()))

        val group = JSONArray(CoreSnapshots.encodeGroups(groups)).getJSONObject(0)

        assertFalse(group.has("selected"))
    }

    @Test
    fun `no core is an empty array, not an error`() {
        assertEquals(0, JSONArray(CoreSnapshots.NO_GROUPS).length())
    }

    // ── /traffic and /connections ─────────────────────────────────────────

    @Test
    fun `a traffic tick names rates and totals apart`() {
        val json = JSONObject(CoreSnapshots.encodeTraffic(1, 2, 3, 4, 5))

        assertEquals(1, json.getLong("up"))
        assertEquals(2, json.getLong("down"))
        assertEquals(3, json.getLong("upTotal"))
        assertEquals(4, json.getLong("downTotal"))
        assertEquals(5, json.getLong("at"))
    }

    @Test
    fun `a connection row carries every column of the connections screen`() {
        val row = ConnectionRow("id1", "example.org:443", "final", "Finland", 10, 20, 30, "tcp")

        val json = JSONArray(CoreSnapshots.encodeConnections(listOf(row))).getJSONObject(0)

        assertEquals(
            setOf("id", "host", "rule", "outbound", "up", "down", "start", "network"),
            json.fieldNames(),
        )
        assertEquals("example.org:443", json.getString("host"))
        assertEquals(20, json.getLong("down"))
    }

    // ── /logs ─────────────────────────────────────────────────────────────

    @Test
    fun `log lines carry a level only when the core gave a real one`() {
        val lines = JSONArray(CoreSnapshots.encodeLogs(listOf("warn" to "slow", null to "plain")))

        assertEquals("warn", lines.getJSONObject(0).getString("level"))
        assertEquals("slow", lines.getJSONObject(0).getString("message"))
        assertFalse(lines.getJSONObject(1).has("level"))
        assertTrue(lines.getJSONObject(1).has("at"))
    }

    @Test
    fun `log levels are logrus numbers and zero is not a panic`() {
        assertNull(CoreSnapshots.logLevelName(0))
        assertEquals("fatal", CoreSnapshots.logLevelName(1))
        assertEquals("error", CoreSnapshots.logLevelName(2))
        assertEquals("warn", CoreSnapshots.logLevelName(3))
        assertEquals("info", CoreSnapshots.logLevelName(4))
        assertEquals("debug", CoreSnapshots.logLevelName(5))
        assertEquals("trace", CoreSnapshots.logLevelName(6))
        assertNull(CoreSnapshots.logLevelName(7))
    }

    @Test
    fun `the log threshold is the level the config names`() {
        assertEquals(4, CoreSnapshots.logThreshold("""{"log":{"level":"info"}}"""))
        assertEquals(3, CoreSnapshots.logThreshold("""{"log":{"level":"warning"}}"""))
        assertEquals(2, CoreSnapshots.logThreshold("""{"log":{"level":"error"}}"""))
    }

    @Test
    fun `a disabled log lets nothing through`() {
        assertEquals(
            CoreSnapshots.LOG_NONE,
            CoreSnapshots.logThreshold("""{"log":{"disabled":true,"level":"info"}}"""),
        )
    }

    @Test
    fun `no level, or no log at all, is trace, as in sing-box`() {
        assertEquals(6, CoreSnapshots.logThreshold("""{"log":{}}"""))
        assertEquals(6, CoreSnapshots.logThreshold("""{"outbounds":[]}"""))
        assertEquals(6, CoreSnapshots.logThreshold("not json"))
    }

    // ── url tests ─────────────────────────────────────────────────────────

    private val groups = listOf(
        GroupSnapshot(
            tag = "select",
            type = "selector",
            selected = "Finland",
            selectable = true,
            items = listOf(
                GroupItemSnapshot("Finland", "vless", 124, urlTestTime = 1_000),
                GroupItemSnapshot("Latvia", "vless", 0, urlTestTime = 1_000),
            ),
        ),
        GroupSnapshot(
            tag = "auto",
            type = "urltest",
            selected = "Lithuania",
            selectable = false,
            items = listOf(GroupItemSnapshot("Lithuania", "trojan", 83, urlTestTime = 1_005)),
        ),
    )

    @Test
    fun `a delay measured in this round is the answer`() {
        assertEquals(124L, CoreSnapshots.freshDelay(groups, "select", "Finland", since = 1_000))
    }

    @Test
    fun `a delay from before the round is the previous answer, not this one`() {
        assertNull(CoreSnapshots.freshDelay(groups, "select", "Finland", since = 1_001))
    }

    @Test
    fun `a zero delay is never measured, not instant`() {
        assertNull(CoreSnapshots.freshDelay(groups, "select", "Latvia", since = 0))
    }

    @Test
    fun `an outbound missing from the named group is found in any other`() {
        assertEquals(83L, CoreSnapshots.freshDelay(groups, "select", "Lithuania", since = 1_000))
    }

    @Test
    fun `an outbound nobody knows has no delay`() {
        assertNull(CoreSnapshots.freshDelay(groups, "select", "Estonia", since = 0))
    }
}
