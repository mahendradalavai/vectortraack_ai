package com.example.kitten

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Process
import android.net.Uri
import android.provider.AlarmClock
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.example.kitten.overlay.FloatingOverlayService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the small `kitten/app_awareness`, `kitten/screen_capture`, and
 * `kitten/phone_capabilities` and `kitten/floating_overlay` channels.
 *
 * Usage stats need the GET_USAGE_STATS app-op, which Flutter plugins cannot
 * reach generically, and screen capture needs the projection consent dialog
 * plus a foreground service, so these few lines live beside the app's own
 * activity instead of pulling in whole dependencies. Every method fails soft so
 * the Dart side never has to guard against a crash.
 */
class MainActivity : FlutterActivity() {

    companion object {
    const val EXTRA_ASSISTANT_COMMAND = "assistant_command"

        /** Set by [FloatingKittenService] when the cat is tapped over another app. */
        const val EXTRA_APP_CONTEXT_PACKAGE = "app_context_package"
        const val EXTRA_APP_CONTEXT_LABEL = "app_context_label"
        const val EXTRA_APP_CONTEXT_LINE = "app_context_line"

        private const val AWARENESS_CHANNEL = "kitten/app_awareness"
        private const val SCREEN_CHANNEL = "kitten/screen_capture"
        private const val PHONE_CHANNEL = "kitten/phone_capabilities"
        private const val OVERLAY_CHANNEL = "kitten/floating_overlay"
        private const val CAPTURE_REQUEST_CODE = 40217

        /**
         * How far back to look for a resumed app. Bounded so the reported app
         * stays plausibly "what you were just doing" rather than a stale
         * leftover from hours ago.
         */
        private const val WINDOW_MS = 10 * 60 * 1000L
    }

    /** The channel result waiting for the current capture, if any. */
    private var pendingCaptureResult: MethodChannel.Result? = null
    private var overlayChannel: MethodChannel? = null

    /**
     * The app the floating Kitten handed over, waiting to be taken.
     *
     * Stashed rather than only pushed because tapping the cat usually
     * cold-starts this activity: the intent arrives before Flutter has
     * registered its channel handler, so a push on its own would be dropped.
     * The Dart side takes the stash once it is ready and acknowledges it, so a
     * warm start is not delivered twice.
     */
    private var pendingAppContext: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AWARENESS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openUsageAccessSettings" -> result.success(openUsageAccessSettings())
                    "foregroundApp" -> result.success(foregroundApp())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(isCaptureSupported())
                    "captureScreen" -> beginScreenCapture(result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PHONE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openDialer" -> openDialer(call.argument<String>("phoneNumber"), result)
                    "composeMessage" -> composeMessage(
                        call.argument<String>("phoneNumber"),
                        call.argument<String>("message"),
                        result
                    )
                    "setAlarm" -> setAlarm(
                        call.argument<Int>("hour"),
                        call.argument<Int>("minute"),
                        call.argument<String>("message"),
                        result
                    )
                    "setTimer" -> setTimer(
                        call.argument<Int>("seconds"),
                        call.argument<String>("message"),
                        result
                    )
                    "openApp" -> openApp(call.argument<String>("packageName"), result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    "hasOverlayPermission" -> result.success(hasOverlayPermission())
                    "openOverlaySettings" -> result.success(openOverlaySettings())
                    "startFloatingKitten" -> result.success(startFloatingKitten())
                    "stopFloatingKitten" -> result.success(stopFloatingKitten())
                    "isFloatingKittenRunning" -> result.success(
                        FloatingOverlayService.isRunning() || FloatingKittenService.isRunning()
                    )
                    "takeAppContext" -> result.success(consumeAppContext())
                    "acknowledgeAppContext" -> {
                        pendingAppContext = null
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kitten/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasMicrophonePermission" -> result.success(
                        checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
                            android.content.pm.PackageManager.PERMISSION_GRANTED
                    )
                    "openMicrophoneSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            }

        overlayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kitten/background_assistant"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(BackgroundAssistantService.isEnabled(this))
                    "start" -> result.success(startBackgroundAssistant())
                    "stop" -> result.success(stopBackgroundAssistant())
                    else -> result.notImplemented()
                }
            }
        }
        deliverAssistantCommand(intent)
        // Not pushed yet: on a cold start nothing is listening.
        deliverAppContext(intent, push = false)
    }

    private fun openAppSettings(): Boolean {
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName")
                )
            )
            true
        } catch (error: Exception) {
            false
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverAssistantCommand(intent)
        deliverAppContext(intent, push = true)
    }

    /**
     * Records the app the floating Kitten was talking about when it was tapped,
     * so the conversation can open already knowing where the user is.
     */
    private fun deliverAppContext(intent: Intent?, push: Boolean) {
        val target = intent ?: return
        val handedOver = target.getStringExtra(EXTRA_APP_CONTEXT_PACKAGE) ?: return
        val label = target.getStringExtra(EXTRA_APP_CONTEXT_LABEL) ?: ""
        val line = target.getStringExtra(EXTRA_APP_CONTEXT_LINE) ?: ""
        target.removeExtra(EXTRA_APP_CONTEXT_PACKAGE)
        target.removeExtra(EXTRA_APP_CONTEXT_LABEL)
        target.removeExtra(EXTRA_APP_CONTEXT_LINE)

        val context = mapOf(
            "packageName" to handedOver,
            "label" to label,
            "line" to line
        )
        pendingAppContext = context
        if (push) overlayChannel?.invokeMethod("appContextOpened", context)
    }

    /** Hands over the stashed app and clears it, so it is only used once. */
    private fun consumeAppContext(): Map<String, String>? {
        val context = pendingAppContext
        pendingAppContext = null
        return context
    }

    private fun deliverAssistantCommand(intent: Intent?) {
        val command = intent?.getStringExtra(EXTRA_ASSISTANT_COMMAND) ?: return
        val channel = overlayChannel
        if (channel == null) {
            intent?.removeExtra(EXTRA_ASSISTANT_COMMAND)
            return
        }
        channel.invokeMethod("assistantCommand", command)
        intent.removeExtra(EXTRA_ASSISTANT_COMMAND)
    }

    private fun startBackgroundAssistant(): Boolean {
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) return false
        return try {
            BackgroundAssistantService.setEnabled(this, true)
            val intent = Intent(this, BackgroundAssistantService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(this, intent)
            } else {
                startService(intent)
            }
            true
        } catch (error: Exception) {
            BackgroundAssistantService.setEnabled(this, false)
            false
        }
    }

    private fun stopBackgroundAssistant(): Boolean {
        BackgroundAssistantService.setEnabled(this, false)
        return stopService(Intent(this, BackgroundAssistantService::class.java))
    }

    private fun hasOverlayPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    private fun openOverlaySettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
            true
        } catch (error: Exception) {
            false
        }
    }

    private fun startFloatingKitten(): Boolean {
        if (!hasOverlayPermission()) return false
        return try {
            FloatingOverlayService.setEnabled(this, true)
            FloatingKittenService.setEnabled(this, false)
            stopService(Intent(this, FloatingKittenService::class.java))
            val intent = Intent(this, FloatingOverlayService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(this, intent)
            } else {
                startService(intent)
            }
            true
        } catch (error: Exception) {
            FloatingOverlayService.setEnabled(this, false)
            false
        }
    }

    private fun stopFloatingKitten(): Boolean {
        FloatingOverlayService.setEnabled(this, false)
        FloatingKittenService.setEnabled(this, false)
        return try {
            stopService(Intent(this, FloatingOverlayService::class.java))
            stopService(Intent(this, FloatingKittenService::class.java))
            true
        } catch (error: Exception) {
            false
        }
    }

    private fun openDialer(phoneNumber: String?, result: MethodChannel.Result) {
        if (phoneNumber.isNullOrBlank()) {
            result.success(actionFailure("A phone number is required."))
            return
        }
        launchIntent(
            Intent(Intent.ACTION_DIAL, Uri.parse("tel:${Uri.encode(phoneNumber)}")),
            result
        )
    }

    private fun composeMessage(
        phoneNumber: String?,
        message: String?,
        result: MethodChannel.Result
    ) {
        if (phoneNumber.isNullOrBlank() || message.isNullOrBlank()) {
            result.success(actionFailure("A phone number and message are required."))
            return
        }
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:${Uri.encode(phoneNumber)}"))
            .putExtra("sms_body", message)
        launchIntent(intent, result)
    }

    private fun setAlarm(
        hour: Int?,
        minute: Int?,
        message: String?,
        result: MethodChannel.Result
    ) {
        if (hour == null || minute == null || hour !in 0..23 || minute !in 0..59) {
            result.success(actionFailure("The alarm time is invalid."))
            return
        }
        val intent = Intent(AlarmClock.ACTION_SET_ALARM)
            .putExtra(AlarmClock.EXTRA_HOUR, hour)
            .putExtra(AlarmClock.EXTRA_MINUTES, minute)
            .putExtra(AlarmClock.EXTRA_SKIP_UI, false)
        if (!message.isNullOrBlank()) intent.putExtra(AlarmClock.EXTRA_MESSAGE, message)
        launchIntent(intent, result)
    }

    private fun setTimer(
        seconds: Int?,
        message: String?,
        result: MethodChannel.Result
    ) {
        if (seconds == null || seconds < 1) {
            result.success(actionFailure("The timer must be at least one second."))
            return
        }
        val intent = Intent(AlarmClock.ACTION_SET_TIMER)
            .putExtra(AlarmClock.EXTRA_LENGTH, seconds)
            .putExtra(AlarmClock.EXTRA_SKIP_UI, false)
        if (!message.isNullOrBlank()) intent.putExtra(AlarmClock.EXTRA_MESSAGE, message)
        launchIntent(intent, result)
    }

    private fun openApp(packageName: String?, result: MethodChannel.Result) {
        if (packageName.isNullOrBlank()) {
            result.success(actionFailure("An app package name is required."))
            return
        }
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        if (intent == null) {
            result.success(actionFailure("That app is not installed or cannot be opened."))
            return
        }
        launchIntent(intent, result)
    }

    private fun launchIntent(intent: Intent, result: MethodChannel.Result) {
        try {
            if (intent.resolveActivity(packageManager) == null) {
                result.success(actionFailure("No app on this device can handle that action."))
                return
            }
            startActivity(intent)
            result.success(actionSuccess())
        } catch (error: Exception) {
            result.success(actionFailure(error.message ?: "The action could not be opened."))
        }
    }

    private fun actionSuccess(): Map<String, Any> = mapOf(
        "success" to true,
        "message" to "Opened the system app for confirmation."
    )

    private fun actionFailure(message: String): Map<String, Any> = mapOf(
        "success" to false,
        "message" to message
    )

    /** Whether this device can capture the screen at all. */
    private fun isCaptureSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP

    /**
     * Asks the system for projection consent, then hands the grant to
     * [ScreenCaptureService], which must be a running foreground service of the
     * mediaProjection type before Android allows the projection to be used.
     *
     * Completes with the JPEG bytes, or null when the user declined.
     */
    private fun beginScreenCapture(result: MethodChannel.Result) {
        if (pendingCaptureResult != null) {
            result.error("busy", "A capture is already in progress.", null)
            return
        }

        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
            as? MediaProjectionManager
        if (manager == null) {
            result.success(null)
            return
        }

        pendingCaptureResult = result
        try {
            startActivityForResult(
                manager.createScreenCaptureIntent(),
                CAPTURE_REQUEST_CODE
            )
        } catch (error: Exception) {
            pendingCaptureResult = null
            result.error("capture_failed", error.message, null)
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CAPTURE_REQUEST_CODE) return

        val result = pendingCaptureResult
        pendingCaptureResult = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            // The user said no: that is a normal outcome, not an error.
            result.success(null)
            return
        }

        ScreenCaptureService.onCaptured = { bytes -> result.success(bytes) }
        val serviceIntent = Intent(this, ScreenCaptureService::class.java)
            .putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
            .putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)

        try {
            ContextCompat.startForegroundService(this, serviceIntent)
        } catch (error: Exception) {
            ScreenCaptureService.onCaptured = null
            result.error("capture_failed", error.message, null)
        }
    }

    /** Whether the user has granted usage access in system settings. */
    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return false

        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }

        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Opens the system screen where usage access is granted. */
    private fun openUsageAccessSettings(): Boolean {
        return try {
            startActivity(
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (error: Exception) {
            false
        }
    }

    /**
     * The app the user most recently used, excluding Kitten itself.
     *
     * Kitten is usually the app in the foreground while it asks, so reporting
     * "which app resumed last" would always answer "Kitten". The useful answer
     * is the last *other* app, which is also what survives the user switching
     * back to Kitten.
     */
    private fun foregroundApp(): Map<String, String>? {
        if (!hasUsageAccess()) return null

        val usageStats = getSystemService(Context.USAGE_STATS_SERVICE)
            as? UsageStatsManager ?: return null

        val now = System.currentTimeMillis()
        val events = try {
            usageStats.queryEvents(now - WINDOW_MS, now)
        } catch (error: Exception) {
            return null
        } ?: return null

        var lastOtherPackage: String? = null
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (!isResumeEvent(event.eventType)) continue
            if (event.packageName == packageName) continue
            lastOtherPackage = event.packageName
        }

        val resolved = lastOtherPackage ?: return null
        return mapOf(
            "packageName" to resolved,
            "label" to appLabel(resolved)
        )
    }

    /**
     * Whether an event means "this activity came to the front".
     *
     * `MOVE_TO_FOREGROUND` is deprecated in favour of `ACTIVITY_RESUMED`, but
     * they share the same value, so testing one covers both.
     */
    private fun isResumeEvent(eventType: Int): Boolean {
        @Suppress("DEPRECATION")
        return eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
    }

    /**
     * The app's display name, or an empty string when Android will not let us
     * see the package. The app deliberately does not request
     * QUERY_ALL_PACKAGES, so unknown packages fall back to a name derived from
     * the package id on the Dart side.
     */
    private fun appLabel(target: String): String {
        return try {
            val info = packageManager.getApplicationInfo(target, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (error: PackageManager.NameNotFoundException) {
            ""
        }
    }
}
