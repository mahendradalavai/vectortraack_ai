package com.example.kitten.overlay

import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.unit.dp
import com.example.kitten.MainActivity
import com.example.kitten.R
import com.example.kitten.ui.character.FloatingKittenCharacter
import com.example.kitten.ui.character.KittenAnimationController
import com.example.kitten.ui.character.KittenState
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Android Foreground Service hosting the native Jetpack Compose Floating Kitten
 * inside a WindowManager overlay.
 *
 * Implements:
 * - WindowManager TYPE_APPLICATION_OVERLAY
 * - Smooth touch dragging with scale-up and pulse ring
 * - Magnetic edge snapping upon release (snaps to closest left or right edge with margin)
 * - Animated speech bubble and state transitions
 * - Seamless tap hand-off to MainActivity
 */
class FloatingOverlayService : Service() {

    companion object {
        const val CHANNEL_ID = "kitten_floating_overlay_compose"
        const val NOTIFICATION_ID = 7402
        private const val PREFS = "kitten_floating_overlay_prefs"
        private const val KEY_ENABLED = "overlay_enabled"
        private const val KEY_LAST_Y = "last_y_pos"

        private const val CAT_WIDTH_DP = 100
        private const val CAT_HEIGHT_DP = 140 // Room for speech bubble + 80dp kitten
        private const val EDGE_MARGIN_DP = 16

        @Volatile
        private var running = false

        fun isRunning(): Boolean = running

        fun isEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

        fun setEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_ENABLED, enabled)
                .apply()
        }

        fun saveLastY(context: Context, y: Int) {
            context.getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .putInt(KEY_LAST_Y, y)
                .apply()
        }

        fun getLastY(context: Context, defaultY: Int): Int =
            context.getSharedPreferences(PREFS, MODE_PRIVATE).getInt(KEY_LAST_Y, defaultY)
    }

    private lateinit var windowManager: WindowManager
    private var composeView: ComposeView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private val lifecycleOwner = OverlayLifecycleOwner()
    private val kittenController = KittenAnimationController()

    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false
    private var touchSlop = 0

    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }

        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                createNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, createNotification())
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        touchSlop = ViewConfiguration.get(this).scaledTouchSlop
        lifecycleOwner.onCreate()

        initOverlayView()
        lifecycleOwner.onResume()
        running = true

        // Initial friendly greeting
        kittenController.setDialogue("Hey! What are you doing today? 😺", durationMs = 6500L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val dialogueExtra = intent?.getStringExtra("dialogue")
        val stateExtra = intent?.getStringExtra("state")

        if (!stateExtra.isNullOrBlank()) {
            kittenController.setState(stateExtra)
        }
        if (!dialogueExtra.isNullOrBlank()) {
            kittenController.setDialogue(dialogueExtra)
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        lifecycleOwner.onPause()
        lifecycleOwner.onDestroy()
        composeView?.let {
            runCatching { windowManager.removeView(it) }
        }
        composeView = null
        layoutParams = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun initOverlayView() {
        val density = resources.displayMetrics.density
        val widthPx = (CAT_WIDTH_DP * density).roundToInt()
        val heightPx = (CAT_HEIGHT_DP * density).roundToInt()
        val bounds = getScreenBounds()

        val savedY = getLastY(this, bounds.height() / 3)
        val defaultX = bounds.width() - widthPx - (EDGE_MARGIN_DP * density).roundToInt()

        val params = WindowManager.LayoutParams(
            widthPx,
            heightPx,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = defaultX.coerceIn(0, (bounds.width() - widthPx).coerceAtLeast(0))
            y = savedY.coerceIn(0, (bounds.height() - heightPx).coerceAtLeast(0))
        }

        val view = ComposeView(this).apply {
            lifecycleOwner.attachToView(this)
            setContent {
                FloatingKittenCharacter(
                    state = kittenController.state,
                    dialogue = kittenController.dialogue,
                    isDragging = kittenController.isDragging,
                    size = 80.dp,
                    onTap = {
                        openMainActivity()
                    }
                )
            }
        }

        view.setOnTouchListener { _, event ->
            handleTouch(event)
        }

        composeView = view
        layoutParams = params
        windowManager.addView(view, params)
    }

    private fun handleTouch(event: MotionEvent): Boolean {
        val params = layoutParams ?: return false
        val view = composeView ?: return false

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                initialX = params.x
                initialY = params.y
                initialTouchX = event.rawX
                initialTouchY = event.rawY
                isDragging = false
                return true
            }

            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - initialTouchX
                val dy = event.rawY - initialTouchY

                if (!isDragging && (abs(dx) > touchSlop || abs(dy) > touchSlop)) {
                    isDragging = true
                    kittenController.isDragging = true
                }

                if (isDragging) {
                    val bounds = getScreenBounds()
                    params.x = (initialX + dx.roundToInt())
                    params.y = (initialY + dy.roundToInt())
                        .coerceIn(0, (bounds.height() - params.height).coerceAtLeast(0))
                    try {
                        windowManager.updateViewLayout(view, params)
                    } catch (_: Exception) {}
                }
                return true
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (isDragging) {
                    kittenController.isDragging = false
                    isDragging = false
                    // Magnetic Edge Snap: smoothly animate to the nearest screen edge
                    snapToNearestEdge()
                } else {
                    // Tap action
                    openMainActivity()
                }
                return true
            }
        }
        return false
    }

    /**
     * Magnetic Edge Snapping:
     * Calculates whether the kitten is closer to the left or right screen border,
     * and animates params.x smoothly with a deceleration curve.
     */
    private fun snapToNearestEdge() {
        val params = layoutParams ?: return
        val view = composeView ?: return
        val bounds = getScreenBounds()
        val density = resources.displayMetrics.density
        val marginPx = (EDGE_MARGIN_DP * density).roundToInt()

        val leftSnapX = marginPx
        val rightSnapX = (bounds.width() - params.width - marginPx).coerceAtLeast(marginPx)

        val currentCenterX = params.x + (params.width / 2)
        val targetX = if (currentCenterX < bounds.width() / 2) leftSnapX else rightSnapX

        saveLastY(this, params.y)

        val startX = params.x
        val animator = ValueAnimator.ofInt(startX, targetX).apply {
            duration = 250L
            interpolator = DecelerateInterpolator()
            addUpdateListener { va ->
                val currentAnimatedX = va.animatedValue as Int
                params.x = currentAnimatedX
                try {
                    windowManager.updateViewLayout(view, params)
                } catch (_: Exception) {}
            }
        }
        animator.start()
    }

    private fun openMainActivity() {
        kittenController.clearDialogue()
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(intent)
    }

    private fun getScreenBounds(): Rect {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            windowManager.currentWindowMetrics.bounds
        } else {
            @Suppress("DEPRECATION")
            val metrics = DisplayMetrics().also { windowManager.defaultDisplay.getMetrics(it) }
            Rect(0, 0, metrics.widthPixels, metrics.heightPixels)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Kitty AI Floating Character",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Maintains the floating Kitty AI character overlay"
            setShowBadge(false)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Kitty AI Floating")
            .setContentText("Kitten is watching over your screen")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
