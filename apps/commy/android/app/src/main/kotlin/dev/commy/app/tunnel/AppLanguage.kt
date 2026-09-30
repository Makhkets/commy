package dev.commy.app.tunnel

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * The language the user picked inside the app, for the strings Android draws
 * without Flutter: the tunnel notification and its channels, the alerts, the
 * Quick Settings tile.
 *
 * Appearance → Language used to switch the Flutter screens only. These strings
 * come from `values` and `values-ru` and followed the system locale, so an
 * English phone with Commy in Russian showed a Russian app and an English
 * notification, and the other way round.
 *
 * The choice arrives from Dart through the `setLocale` method and is kept here
 * rather than asked for each time: the tile and a boot reminder are drawn
 * while Flutter is not running at all. Not a secret (rule R2): a language tag.
 *
 * `LocaleManager.setApplicationLocales` would do the same from API 33 only,
 * and would move the Flutter view's locale too; one stored tag covers every
 * API level with one code path.
 */
internal object AppLanguage {

    private const val FILE = "commy.language"
    private const val KEY_TAG = "tag"

    /**
     * The locale a stored tag names, or null for "follow the system".
     *
     * Dart sends an empty string for the system choice. A tag that names no
     * language is read the same way, so it cannot leave the notification in
     * the resources' default by accident.
     */
    fun localeOf(tag: String?): Locale? {
        val trimmed = tag?.trim().orEmpty()
        if (trimmed.isEmpty()) {
            return null
        }
        return Locale.forLanguageTag(trimmed).takeIf { it.language.isNotEmpty() }
    }

    /** The stored tag; null when the user follows the system. */
    fun tag(context: Context): String? =
        prefs(context).getString(KEY_TAG, null)?.takeIf { localeOf(it) != null }

    fun store(context: Context, tag: String?) {
        val editor = prefs(context).edit()
        if (localeOf(tag) == null) {
            editor.remove(KEY_TAG)
        } else {
            editor.putString(KEY_TAG, tag?.trim())
        }
        editor.apply()
    }

    /**
     * [context] with its resources in [tag]'s language, or [context] itself
     * when the user follows the system.
     *
     * Only for reading strings. Everything else — a notification builder, a
     * pending intent, a colour — keeps the real context.
     */
    fun localize(context: Context, tag: String?): Context {
        val locale = localeOf(tag) ?: return context
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocale(locale)
        return context.createConfigurationContext(configuration)
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)
}
