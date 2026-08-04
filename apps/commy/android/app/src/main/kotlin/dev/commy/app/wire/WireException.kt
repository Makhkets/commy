package dev.commy.app.wire

/**
 * A failure that already knows which wire code it becomes.
 *
 * Everything the method channel can answer with is one of these. `Wire.Errors`
 * is a closed set on purpose: Dart maps each code onto a typed `CommyFailure`,
 * and an unmapped code degrades to `UnknownFailure`, which is the difference
 * between "grant the VPN permission" and "something went wrong".
 *
 * @param code one of `Wire.Errors`.
 * @param detail shown to the user through `CoreCrashedFailure.log` and
 *   `ConfigInvalidFailure.detail`. Never put credentials or a config in here.
 */
internal class WireException(
    val code: String,
    val detail: String,
    cause: Throwable? = null,
) : Exception(detail, cause) {

    companion object {
        /**
         * Wraps anything that came out of libbox or the Android framework.
         *
         * Uses the exception's own message, not its class name: the message is
         * what sing-box wrote about the config, and it is the only part a user
         * can act on.
         */
        fun from(code: String, error: Throwable): WireException = WireException(
            code = code,
            detail = error.message?.takeIf { it.isNotBlank() } ?: error.javaClass.simpleName,
            cause = error,
        )
    }
}
