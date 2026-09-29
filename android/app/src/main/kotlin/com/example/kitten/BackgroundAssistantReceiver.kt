package com.example.kitten

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

/** Re-arms the user's explicitly enabled listener after unlock or reboot. */
class BackgroundAssistantReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_USER_UNLOCKED &&
            intent?.action != Intent.ACTION_BOOT_COMPLETED
        ) return
        if (FloatingKittenService.isEnabled(context) &&
            android.provider.Settings.canDrawOverlays(context)
        ) {
            val overlayIntent = Intent(context, FloatingKittenService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, overlayIntent)
            } else {
                context.startService(overlayIntent)
            }
        }

        if (!BackgroundAssistantService.isEnabled(context) ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO,
            ) != PackageManager.PERMISSION_GRANTED
        ) return

        val serviceIntent = Intent(context, BackgroundAssistantService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(context, serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
