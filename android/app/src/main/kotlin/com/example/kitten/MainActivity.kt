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
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the small `kitten/app_awareness` and `kitten/screen_capture` channels.
 *
 * Usage stats need the GET_USAGE_STATS app-op, which Flutter plugins cannot
 * reach generically, and screen capture needs the projection consent dialog
 * plus a foreground service, so these few lines live beside the app's own
 * activity instead of pulling in whole dependencies. Every method fails soft so
 * the Dart side never has to guard against a crash.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val AWARENESS_CHANNEL = "kitten/app_awareness"
        private const val SCREEN_CHANNEL = "kitten/screen_capture"
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
    }

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
