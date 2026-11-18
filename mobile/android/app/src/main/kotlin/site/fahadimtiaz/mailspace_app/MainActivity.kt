package site.fahadimtiaz.mailspace_app

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    // Android 8+: notifications need "channels". High importance = pops up on screen,
    // like WhatsApp. Calls ring with the phone's ringtone. (Names show in phone Settings.)
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val mail = NotificationChannel("mail", "New email", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "New emails and alerts"
        }
        val calls = NotificationChannel("calls", "Calls", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Incoming and missed voice and video calls"
            enableVibration(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
        }
        manager.createNotificationChannels(listOf(mail, calls))
    }

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
