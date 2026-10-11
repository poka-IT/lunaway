package legal.p2p.lunaway

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.util.Log
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.TransitionOptions

class MainActivity : FlutterActivity() {
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The free room of the volume the offline maps go to, read before a
        // download so that a pack never fills the device.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lunaway/files")
            .setMethodCallHandler { call, result ->
                val path = call.arguments as? String
                when {
                    call.method != "freeBytes" -> result.notImplemented()
                    path == null -> result.error("args", "a folder is needed", null)
                    else ->
                        try {
                            result.success(StatFs(path).availableBytes)
                        } catch (e: IllegalArgumentException) {
                            result.error("io", e.message, null)
                        }
                }
            }

        // Android 13 and later show what was copied themselves: the app then
        // says nothing more, rather than the same text twice.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lunaway/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showsCopies" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                    else -> result.notImplemented()
                }
            }

        // The guidance's map places its labels without fading them: with the
        // fades, MapLibre keeps drawing between two moves of the camera
        // whatever limit of frames the app set, and the guidance's cadence
        // does not hold (plan/research/124-cadence-carte-guidage.md). The
        // maplibre_gl plugin has no call for it; the map is the one whose
        // style holds the source the app names, and the fades of the other
        // maps (the main map, the preview) stay as they are.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lunaway/map")
            .setMethodCallHandler { call, result ->
                val source = call.argument<String>("source")
                val on = call.argument<Boolean>("on")
                when {
                    call.method != "labelFades" -> result.notImplemented()
                    source == null || on == null -> result.error("args", "a source and on are needed", null)
                    else ->
                        // Compiled against the library maplibre_gl brings
                        // (build.gradle.kts): a version of it without these
                        // calls answers an error, and the map keeps its fades.
                        try {
                            for (view in mapViews(window.decorView)) {
                                view.getMapAsync { map ->
                                    map.getStyle { style -> fadeLabels(style, source, on) }
                                }
                            }
                            result.success(null)
                        } catch (e: Throwable) {
                            result.error("maplibre", e.toString(), null)
                        }
                }
            }

        // Whether the device has a network, and whether it is metered (a
        // mobile network, a phone's hotspot, a Wi-Fi the user marked as
        // metered): the regions kept offline update on an unmetered one
        // unless the user allows mobile data, and the app asks its servers
        // again as soon as a network comes back rather than a minute later.
        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lunaway/network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "current" -> result.success(networkState(connectivity))
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "lunaway/network/changes")
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                        val main = Handler(Looper.getMainLooper())
                        // The callbacks come on the system's own thread; the
                        // state is read again on the main one, where the
                        // events must be sent.
                        fun tell() {
                            main.post { events.success(networkState(connectivity)) }
                        }
                        val callback =
                            object : ConnectivityManager.NetworkCallback() {
                                override fun onAvailable(network: Network) = tell()

                                override fun onLost(network: Network) = tell()

                                override fun onCapabilitiesChanged(
                                    network: Network,
                                    capabilities: NetworkCapabilities,
                                ) = tell()
                            }
                        networkCallback?.let { connectivity.unregisterNetworkCallback(it) }
                        connectivity.registerDefaultNetworkCallback(callback)
                        networkCallback = callback
                    }

                    override fun onCancel(arguments: Any?) {
                        networkCallback?.let { connectivity.unregisterNetworkCallback(it) }
                        networkCallback = null
                    }
                },
            )
    }

    override fun onDestroy() {
        networkCallback?.let {
            (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                .unregisterNetworkCallback(it)
        }
        networkCallback = null
        super.onDestroy()
    }

    /** The fades of the labels of [style] set to [on] when it holds [source]. */
    private fun fadeLabels(style: Style, source: String, on: Boolean) {
        try {
            if (style.getSource(source) == null) return
            val now = style.transition
            style.transition = TransitionOptions(now.duration, now.delay, on)
        } catch (e: Throwable) {
            // Called later on the main thread, out of the channel's reach.
            Log.w("lunaway", "label fades: $e")
        }
    }

    /** The maps under [view]: maplibre_gl's views sit in the window's hierarchy. */
    private fun mapViews(view: View): List<MapView> =
        when (view) {
            is MapView -> listOf(view)
            is ViewGroup -> (0 until view.childCount).flatMap { mapViews(view.getChildAt(it)) }
            else -> emptyList()
        }

    private fun networkState(connectivity: ConnectivityManager): Map<String, Boolean> {
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        val connected =
            capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        return mapOf("connected" to connected, "metered" to connectivity.isActiveNetworkMetered)
    }
}
