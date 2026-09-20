package com.example.kitten

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the small `kitten/app_awareness` channel.
 *
 * Usage stats need the GET_USAGE_STATS app-op, which Flutter plugins cannot
 * reach generically, so these few lines live beside the app's own activity
 * instead of pulling in a whole dependency. Every method fails soft so the
 * Dart side never has to guard against a crash.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "kitten/app_awareness"

        /**
         * How far back to look for a resumed app. Bounded so the reported app
         * stays plausibly "what you were just doing" rather than a stale
         * leftover from hours ago.
         */
        private const val WINDOW_MS = 10 * 60 * 1000L
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openUsageAccessSettings" -> result.success(openUsageAccessSettings())
                    "foregroundApp" -> result.success(foregroundApp())
                    else -> result.notImplemented()
                }
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
