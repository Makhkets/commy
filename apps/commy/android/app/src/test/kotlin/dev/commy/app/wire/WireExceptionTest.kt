package dev.commy.app.wire

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class WireExceptionTest {

    @Test
    fun `a wrapped failure says what the core said`() {
        val cause = IllegalStateException("outbound[0]: unknown transport \"xhttp2\"")

        val error = WireException.from(Wire.Errors.CONFIG_INVALID, cause)

        assertEquals(Wire.Errors.CONFIG_INVALID, error.code)
        assertEquals("outbound[0]: unknown transport \"xhttp2\"", error.detail)
        assertSame(cause, error.cause)
    }

    @Test
    fun `a failure with nothing to say is named by its type`() {
        assertEquals(
            "IllegalStateException",
            WireException.from(Wire.Errors.CORE_CRASHED, IllegalStateException("  ")).detail,
        )
        assertEquals(
            "NullPointerException",
            WireException.from(Wire.Errors.CORE_CRASHED, NullPointerException()).detail,
        )
    }
}
