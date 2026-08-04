package dev.commy.app.wire

/**
 * The Dart side of this contract is `packages/commy_core/lib/src/wire/`, and
 * the contract itself is `packages/commy_core/docs/wire-protocol.md`.
 *
 * Every string here has a twin in a Dart file of the same shape. Neither
 * compiler can see the other, so a typo in a channel name is invisible until a
 * button stops doing anything — which is precisely why both sides keep their
 * strings in one place instead of spelling them out at the call site.
 */
internal object Wire {
    /** Channel names. Matches `WireChannels`. */
    object Channels {
        private const val NAMESPACE = "dev.commy.app"

        /** Dart to Kotlin: the seven methods below. */
        const val METHOD = "$NAMESPACE/core"

        /** Kotlin to Dart: tunnel state. */
        const val STATUS = "$NAMESPACE/status"

        /** Kotlin to Dart: throughput ticks. */
        const val TRAFFIC = "$NAMESPACE/traffic"

        /** Kotlin to Dart: raw core log lines. */
        const val LOGS = "$NAMESPACE/logs"

        /** Kotlin to Dart: full snapshots of the open connections. */
        const val CONNECTIONS = "$NAMESPACE/connections"

        /**
         * Kotlin to Dart: things the Android system handed the app.
         *
         * NOT part of `wire-protocol.md` — that document covers the tunnel, and
         * this channel carries no tunnel state. It exists because a deep link,
         * a shared config file and a Quick Settings "connect" are all inputs
         * that arrive as an `Intent` and have nowhere else to go. Payload shape
         * is in [Intents]. Ignoring the channel entirely is safe: the events
         * are simply never delivered and imports still work by paste and QR.
         */
        const val INTENTS = "$NAMESPACE/intents"
    }

    /** Method names on [Channels.METHOD]. Seven, and no more. */
    object Methods {
        const val START = "start"
        const val STOP = "stop"
        const val RELOAD = "reload"
        const val SELECT = "select"
        const val URL_TEST = "urlTest"
        const val PROXIES = "proxies"
        const val VERSION = "version"
    }

    /** JSON field names. Matches `WireKeys`. */
    object Keys {
        // Method arguments and results.
        const val GROUP = "group"
        const val TAG = "tag"
        const val URL = "url"
        const val TIMEOUT_MS = "timeoutMs"
        const val DELAY_MS = "delayMs"

        // proxies()
        const val TYPE = "type"
        const val SELECTED = "selected"
        const val SELECTABLE = "selectable"
        const val ITEMS = "items"
        const val URL_TEST_DELAY = "urlTestDelay"

        // /status
        const val STATE = "state"
        const val SINCE = "since"
        const val NODE_ID = "nodeId"
        const val REASON = "reason"
        const val CODE = "code"

        // /traffic
        const val UP = "up"
        const val DOWN = "down"
        const val UP_TOTAL = "upTotal"
        const val DOWN_TOTAL = "downTotal"
        const val AT = "at"

        // /logs
        const val LEVEL = "level"
        const val MESSAGE = "message"

        // /connections
        const val ID = "id"
        const val HOST = "host"
        const val RULE = "rule"
        const val OUTBOUND = "outbound"
        const val START = "start"
        const val NETWORK = "network"

        // /intents
        const val KIND = "kind"
        const val URI = "uri"
        const val TEXT = "text"
    }

    /** `/status` state values. Matches `WireStates`. */
    object States {
        const val IDLE = "idle"
        const val STARTING = "starting"
        const val CONNECTED = "connected"
        const val STOPPING = "stopping"
        const val ERROR = "error"

        /**
         * Deliberately absent from this object: `checking`.
         *
         * Dart derives it on top of [CONNECTED] from the first url test. The
         * native side never sends it, so there is no constant for it here.
         */
    }

    /** `/intents` event kinds. */
    object Intents {
        /** A protocol or subscription link: `{"kind":"link","uri":"vless://…"}`. */
        const val LINK = "link"

        /** A config file: `{"kind":"file","uri":"content://…"}`. */
        const val FILE = "file"

        /** Shared plain text: `{"kind":"text","text":"…"}`. */
        const val TEXT = "text"

        /**
         * "The user asked to connect from outside the UI."
         *
         * `{"kind":"connect"}`. Sent when the Quick Settings tile or the boot
         * notification is used while no tunnel is up. Dart owns the profile —
         * the native side cannot start one on its own, because the generated
         * config is a secret and rule R2 keeps it out of native storage.
         */
        const val CONNECT = "connect"
    }

    /** Error codes. A closed set; matches `WireErrorCodes`. */
    object Errors {
        const val PERMISSION_DENIED = "permission_denied"
        const val CONFIG_INVALID = "config_invalid"
        const val CORE_CRASHED = "core_crashed"
        const val HELPER_UNAVAILABLE = "helper_unavailable"
        const val NOT_RUNNING = "not_running"
        const val ALREADY_RUNNING = "already_running"
        const val STORAGE = "storage"
        const val UNKNOWN = "unknown"
    }
}
