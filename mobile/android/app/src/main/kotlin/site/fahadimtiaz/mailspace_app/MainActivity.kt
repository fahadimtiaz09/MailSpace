package site.fahadimtiaz.mailspace_app

import android.app.Activity
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Screen guard for emails (talks to lib/services/screen_guard.dart):
//   "secure" true/false → block screenshots & screen recording (screen turns black)
//   Android 14+ also tells Flutter when a screenshot is taken ("screenshot")
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    // Android 14 (API 34) and newer: the system tells us about screenshots
    private val screenCaptureCallback: Any? =
        if (Build.VERSION.SDK_INT >= 34) Activity.ScreenCaptureCallback {
            channel?.invokeMethod("screenshot", null)
        } else null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mailspace/screen_guard")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "secure" -> {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= 34) {
            registerScreenCaptureCallback(mainExecutor, screenCaptureCallback as Activity.ScreenCaptureCallback)
        }
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= 34) {
            unregisterScreenCaptureCallback(screenCaptureCallback as Activity.ScreenCaptureCallback)
        }
        super.onStop()
    }
}
