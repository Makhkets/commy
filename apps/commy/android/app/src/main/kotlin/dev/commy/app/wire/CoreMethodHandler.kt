package dev.commy.app.wire

import android.content.Context
import dev.commy.app.tunnel.TunnelController
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.nekohasekai.libbox.Libbox
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * The seven methods of `dev.commy.app/core`.
 *
 * Every branch answers exactly once, with `success` or with `error`. A silent
 * path here is a button that does nothing and a future waiting forever, which
 * is worse than any failure code.
 *
 * [scope] is confined to the main looper, so `MethodChannel.Result` is always
 * touched from there.
 */
internal class CoreMethodHandler(
    private val context: Context,
    private val scope: CoroutineScope,
    private val permission: VpnPermission,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in KNOWN) {
            result.notImplemented()
            return
        }
        scope.launch {
            try {
                result.success(dispatch(call))
            } catch (error: CancellationException) {
                // The engine went away mid-call. Nobody is left to answer to.
                throw error
            } catch (error: WireException) {
                result.error(error.code, error.detail, null)
            } catch (error: Throwable) {
                result.error(
                    Wire.Errors.UNKNOWN,
                    error.message ?: error.javaClass.simpleName,
                    null,
                )
            }
        }
    }

    private suspend fun dispatch(call: MethodCall): Any? = when (call.method) {
        Wire.Methods.START -> {
            val config = configArgument(call)
            // Consent first: bringing the service up before asking would show
            // a foreground notification for a tunnel the user is about to
            // refuse.
            permission.ensure(context)
            permission.requestNotifications()
            TunnelController.start(context, config)
            null
        }

        Wire.Methods.STOP -> {
            TunnelController.stop()
            null
        }

        Wire.Methods.RELOAD -> {
            TunnelController.reload(configArgument(call))
            null
        }

        Wire.Methods.SELECT -> {
            val request = jsonArgument(call)
            TunnelController.select(
                group = request.getString(Wire.Keys.GROUP),
                tag = request.getString(Wire.Keys.TAG),
            )
            null
        }

        Wire.Methods.URL_TEST -> {
            val request = jsonArgument(call)
            // `url` is in the request and deliberately unused: libbox measures
            // a group against the probe the config gave that group, and there
            // is no per-call override. It stays on the wire so the Dart side
            // keeps one shape for every platform.
            val delay = TunnelController.urlTest(
                group = request.optString(Wire.Keys.GROUP, DEFAULT_GROUP)
                    .ifBlank { DEFAULT_GROUP },
                tag = request.getString(Wire.Keys.TAG),
                timeoutMs = request.optLong(Wire.Keys.TIMEOUT_MS, DEFAULT_TIMEOUT_MS),
            )
            // An explicit null, not a missing key: "we could not measure it" is
            // an answer, and the screen draws a dash for it.
            JSONObject().put(Wire.Keys.DELAY_MS, delay ?: JSONObject.NULL).toString()
        }

        Wire.Methods.PROXIES -> TunnelController.proxies()

        Wire.Methods.VERSION -> Libbox.version()

        else -> null
    }

    private fun configArgument(call: MethodCall): String = call.arguments as? String
        ?: throw WireException(
            Wire.Errors.CONFIG_INVALID,
            "${call.method} expects the configuration JSON as a string",
        )

    private fun jsonArgument(call: MethodCall): JSONObject {
        val raw = call.arguments as? String ?: throw WireException(
            Wire.Errors.UNKNOWN,
            "${call.method} expects a JSON string argument",
        )
        return runCatching { JSONObject(raw) }.getOrElse {
            throw WireException(Wire.Errors.UNKNOWN, "${call.method} got malformed JSON")
        }
    }

    private companion object {
        /** Matches `SwitchNodeUseCase.defaultGroupTag` and `SingBoxTags.proxyGroup`. */
        const val DEFAULT_GROUP = "proxy"

        const val DEFAULT_TIMEOUT_MS = 5_000L

        val KNOWN = setOf(
            Wire.Methods.START,
            Wire.Methods.STOP,
            Wire.Methods.RELOAD,
            Wire.Methods.SELECT,
            Wire.Methods.URL_TEST,
            Wire.Methods.PROXIES,
            Wire.Methods.VERSION,
        )
    }
}
