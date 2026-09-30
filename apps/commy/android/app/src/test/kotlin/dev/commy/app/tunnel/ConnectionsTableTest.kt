package dev.commy.app.tunnel

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * `/connections` as a subscriber sees it: the current table the moment it
 * subscribes, and an empty one once the tunnel is gone.
 *
 * The Connections tab subscribes when it opens and again on "Refresh". As an
 * event stream the channel answered neither until the table next changed, so
 * with the tunnel down the tab showed a skeleton for good.
 */
class ConnectionsTableTest {

    @Test
    fun `a new subscriber gets the current table straight away`() = runBlocking {
        TunnelController.emitConnections(TABLE)

        assertEquals(TABLE, withTimeout(TIMEOUT_MS) { TunnelController.connections.first() })
    }

    @Test
    fun `a closed bridge leaves an empty table behind`() = runBlocking {
        TunnelController.emitConnections(TABLE)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

        CoreEventBridge(scope, onCoreLost = {}, onTraffic = { _, _ -> }).close()
        scope.cancel()

        assertEquals(
            CoreSnapshots.NO_CONNECTIONS,
            withTimeout(TIMEOUT_MS) { TunnelController.connections.first() },
        )
    }

    @Test
    fun `the empty table is the one the ticker would send for no rows`() {
        assertEquals(CoreSnapshots.encodeConnections(emptyList()), CoreSnapshots.NO_CONNECTIONS)
        assertEquals(0, JSONArray(CoreSnapshots.NO_CONNECTIONS).length())
    }

    private companion object {
        const val TIMEOUT_MS = 1_000L
        const val TABLE = """[{"id":"c-1","host":"example.com:443"}]"""
    }
}
