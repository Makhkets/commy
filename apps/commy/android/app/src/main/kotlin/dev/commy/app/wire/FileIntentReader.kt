package dev.commy.app.wire

import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * Reads the config file an intent handed over, as text for the import sheet.
 *
 * The manifest puts Commy in "Open with" for JSON, YAML and plain-text files
 * and takes files shared to it, and every one of them used to reach Dart as a
 * bare `content://` address that nothing there could open: the app came to
 * the front and did nothing at all. The address is only good while the
 * activity it was handed to is alive — the read grant goes with it — so the
 * file is read here, at once, and what Dart gets is its text, the same event
 * a shared link is. The import sheet then shows that text before anything is
 * stored, as it does for every other way in.
 *
 * Nothing read here is logged: a config file is every credential in it, in
 * the clear (rule R3).
 */
internal object FileIntentReader {

    /**
     * The most a file may hold and still be read.
     *
     * A sing-box export of a few hundred servers is a few hundred kilobytes.
     * Past this it is not a config, and a platform channel is no place to
     * carry it.
     */
    const val MAX_BYTES = 2 * 1024 * 1024

    private const val BYTE_ORDER_MARK = "\uFEFF"

    /**
     * The text of the stream [open] returns, or null when there is none to
     * give: no stream, a stream that failed, a file over [limit] bytes, or one
     * with nothing but whitespace in it.
     *
     * UTF-8 with malformed bytes replaced rather than refused, as the file
     * picker's path in Dart does: a config saved in cp1251 should end on a
     * parse failure the user can read, not on silence. A byte order mark is
     * dropped, since the link parser would take it for part of the first line.
     */
    fun read(limit: Int = MAX_BYTES, open: () -> InputStream?): String? {
        val bytes = try {
            open()?.use { it.readAtMost(limit) }
        } catch (error: Exception) {
            // A provider that is gone, a grant that lapsed, a file that moved:
            // all of them are "could not be read", and Dart says so.
            null
        } ?: return null
        val text = String(bytes, Charsets.UTF_8).removePrefix(BYTE_ORDER_MARK)
        return text.takeIf(String::isNotBlank)
    }

    /** Up to [limit] bytes, or null when there are more than that. */
    private fun InputStream.readAtMost(limit: Int): ByteArray? {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val count = read(buffer)
            if (count < 0) {
                return out.toByteArray()
            }
            if (out.size() + count > limit) {
                return null
            }
            out.write(buffer, 0, count)
        }
    }
}
