package legal.p2p.lunaway

import android.os.Build
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
    }
}
