package dev.commy.app.tunnel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Which language the notification and the tile are drawn in, from the tag the
 * Dart side sends. Getting "follow the system" wrong pins them to one language
 * for good; getting a real tag wrong leaves them in the system's.
 */
class AppLanguageTest {

    @Test
    fun `a language chosen in the app names its locale`() {
        assertEquals("ru", AppLanguage.localeOf("ru")?.language)
        assertEquals("en", AppLanguage.localeOf("en")?.language)
    }

    @Test
    fun `a full tag keeps its region`() {
        val locale = AppLanguage.localeOf("pt-BR")

        assertEquals("pt", locale?.language)
        assertEquals("BR", locale?.country)
    }

    @Test
    fun `the empty tag Dart sends for the system choice is no locale`() {
        assertNull(AppLanguage.localeOf(""))
        assertNull(AppLanguage.localeOf("   "))
        assertNull(AppLanguage.localeOf(null))
    }

    @Test
    fun `a tag that names no language is the system choice, not the default resources`() {
        assertNull(AppLanguage.localeOf("!!"))
    }
}
