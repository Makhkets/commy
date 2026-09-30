package dev.commy.app.wire

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream

class FileIntentReaderTest {

    private val link = "vless://11111111-2222-3333-4444-555555555555@nl-03.example.net:443#NL"

    private fun streamOf(bytes: ByteArray): () -> InputStream = { ByteArrayInputStream(bytes) }

    @Test
    fun `a config file comes back as its text`() {
        val text = "$link\n$link\n"

        assertEquals(text, FileIntentReader.read(open = streamOf(text.toByteArray())))
    }

    @Test
    fun `a byte order mark is not taken for part of the first line`() {
        val bytes = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + link.toByteArray()

        assertEquals(link, FileIntentReader.read(open = streamOf(bytes)))
    }

    @Test
    fun `bytes that are not UTF-8 are replaced, not refused`() {
        // cp1251 for "Сервер": the parser should get to say what is wrong.
        val bytes = byteArrayOf(0xD1.toByte(), 0xE5.toByte(), 0xF0.toByte()) + " $link".toByteArray()

        val text = FileIntentReader.read(open = streamOf(bytes))

        assertEquals("��� $link", text)
    }

    @Test
    fun `a file over the limit is not read`() {
        val bytes = ByteArray(64) { 'a'.code.toByte() }

        assertNull(FileIntentReader.read(limit = 63, open = streamOf(bytes)))
        assertEquals("a".repeat(64), FileIntentReader.read(limit = 64, open = streamOf(bytes)))
    }

    @Test
    fun `a file with nothing in it has nothing to import`() {
        assertNull(FileIntentReader.read(open = streamOf(" \n\t".toByteArray())))
        assertNull(FileIntentReader.read(open = streamOf(ByteArray(0))))
    }

    @Test
    fun `a provider that gives nothing, refuses or breaks is a file that could not be read`() {
        assertNull(FileIntentReader.read { null })
        assertNull(FileIntentReader.read { throw FileNotFoundException("gone") })
        assertNull(FileIntentReader.read { throw SecurityException("no grant") })
        assertNull(
            FileIntentReader.read {
                object : InputStream() {
                    override fun read(): Int = throw IOException("provider died")
                }
            },
        )
    }

    @Test
    fun `the stream is closed after reading`() {
        var closed = false
        val stream = object : ByteArrayInputStream(link.toByteArray()) {
            override fun close() {
                closed = true
                super.close()
            }
        }

        FileIntentReader.read { stream }

        assertEquals(true, closed)
    }
}
