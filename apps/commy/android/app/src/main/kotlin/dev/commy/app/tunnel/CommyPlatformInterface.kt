package dev.commy.app.tunnel

import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.InetAddress
import java.net.InetSocketAddress
import io.nekohasekai.libbox.Notification as CoreNotification

/**
 * What the core asks of Android.
 *
 * Fifteen methods, exactly as they come out of `javap` on the AAR we link — the
 * dump is in docs/libbox-java-api.txt and the reading of it in
 * docs/13-libbox-reference.md. Three methods that every reconstruction from
 * memory adds do not exist here: `packageNameByUid`, `writeLog` and
 * `usePlatformDefaultInterfaceMonitor`. Adding one breaks the link step, not
 * the run.
 *
 * gomobile calls every one of these from a Go thread. None of them may touch
 * Flutter.
 */
internal class CommyPlatformInterface(
    private val service: CommyVpnService,
    private val monitor: DefaultNetworkMonitor,
) : PlatformInterface {

    /**
     * We protect sockets ourselves rather than letting the core guess.
     *
     * Without it the core's own traffic is routed into the tunnel it is trying
     * to build, which is a loop with no error message.
     */
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        if (!service.protect(fd)) {
            throw IllegalStateException("VpnService.protect($fd) was refused")
        }
    }

    override fun openTun(options: TunOptions): Int = service.openTun(options)

    /**
     * `/proc/net` is unreadable from an app on Android 10 and later, so process
     * lookup goes through `ConnectivityManager` instead. Answering true here
     * gets the core a permission denial on every packet.
     */
    override fun useProcFS(): Boolean = false

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw UnsupportedOperationException("connection owner lookup needs Android 10")
        }
        val connectivity = service.getSystemService(ConnectivityManager::class.java)
            ?: throw IllegalStateException("no ConnectivityManager")
        val uid = connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(InetAddress.getByName(sourceAddress), sourcePort),
            InetSocketAddress(InetAddress.getByName(destinationAddress), destinationPort),
        )
        if (uid == INVALID_UID) {
            throw NoSuchElementException("no owner for $sourceAddress:$sourcePort")
        }
        return ConnectionOwner().apply {
            setUserId(uid)
            // Package names come back only for apps the <queries> block in the
            // manifest makes visible to us. An empty list is a valid answer and
            // the core copes: the rule simply does not match by package.
            val names = service.packageManager.packagesForUidOrEmpty(uid)
            setUserName(names.firstOrNull().orEmpty())
            setAndroidPackageNames(StringArray(names))
        }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) =
        monitor.register(listener)

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) =
        monitor.unregister(listener)

    override fun getInterfaces(): NetworkInterfaceIterator = InterfaceArray(monitor.interfaces())

    /** iOS only. Android has no network extension. */
    override fun underNetworkExtension(): Boolean = false

    /**
     * The Apple kill switch. On Android the equivalent is "Block connections
     * without VPN" in system settings, which the user owns and an app cannot
     * set, so there is nothing to report here.
     */
    override fun includeAllNetworks(): Boolean = false

    /**
     * Always null, and that is a decision rather than a gap.
     *
     * From Android 8.1 the SSID is gated behind a location permission. Commy
     * does not declare one — a proxy client asking where you are is precisely
     * the thing this project exists not to do — so there is nothing to read and
     * no point pretending otherwise. Returning null is a supported answer:
     * `CommandServer.needWIFIState()` simply stops asking.
     *
     * The cost: routing rules keyed on a named Wi-Fi network never match, and
     * behave as if the phone were on an unknown network. Reversing that means
     * adding ACCESS_FINE_LOCATION to the manifest, filling this in, and getting
     * the threat-model change signed off — CLAUDE.md §7, point 4.
     */
    override fun readWIFIState(): WIFIState? = null

    /**
     * Empty on purpose.
     *
     * Android hands the system trust store to the Go TLS stack through its own
     * roots already; enumerating it here would cost megabytes of allocation per
     * call and add nothing.
     */
    override fun systemCertificates(): StringIterator = StringArray.EMPTY

    /** No custom DNS transport. The core uses the servers the config names. */
    override fun localDNSTransport(): LocalDNSTransport? = null

    /** Nothing to flush: we run no resolver cache of our own. */
    override fun clearDNSCache() = Unit

    override fun sendNotification(notification: CoreNotification) {
        service.notifications.fromCore(
            identifier = notification.identifier,
            title = notification.title,
            body = notification.body,
            subtitle = notification.subtitle,
        )
    }

    private fun PackageManager.packagesForUidOrEmpty(uid: Int): List<String> =
        runCatching { getPackagesForUid(uid)?.filterNotNull() }.getOrNull().orEmpty()

    private companion object {
        /** `android.os.Process.INVALID_UID`, which is only public from API 31. */
        const val INVALID_UID = -1
    }
}
