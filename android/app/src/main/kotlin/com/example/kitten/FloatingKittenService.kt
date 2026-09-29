package com.example.kitten

import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Displays the compact, user-started Kitten overlay above other apps.
 *
 * The overlay is the app's face away from its own screen, so it does the two
 * visible parts of the conversation flow by itself:
 *
 * 1. It greets the user when it appears (which includes after unlock, because
 *    [BackgroundAssistantReceiver] restarts it there).
 * 2. It watches which app the user opens and says a line about it in a small
 *    speech bubble beside the cat.
 *
 * Neither needs the microphone or the background-listening service: the watch
 * reads Android's own usage events and only runs while the user has granted
 * Usage Access. Tapping the cat hands the app it just talked about to
 * [MainActivity], so the conversation opens already knowing where the user is.
 */
class FloatingKittenService : Service() {

    companion object {
        private const val CHANNEL_ID = "kitten_floating_overlay"
        private const val NOTIFICATION_ID = 7401
        private const val CAT_SIZE_DP = 76
        private const val INITIAL_MARGIN_DP = 16
        private const val PREFS = "kitten_floating_overlay"
        private const val ENABLED = "enabled"

        /** What Kitten says the moment the overlay appears. */
        private const val GREETING = "Hey! What are you doing today?"

        /** How long a line stays on screen before the bubble goes away. */
        private const val BUBBLE_VISIBLE_MS = 6500L

        /** How often the overlay looks for a newly opened app. */
        private const val APP_POLL_MS = 2500L

        /** A beat of quiet so the greeting is read before the first app line. */
        private const val FIRST_APP_CHECK_MS = 4000L

        /**
         * How far back a "moved to foreground" event still counts as *just*
         * opened. Bounded so Kitten never comments on an app the user left a
         * while ago.
         */
        private const val APP_WINDOW_MS = 20_000L

        private const val BUBBLE_MAX_WIDTH_DP = 184
        private const val BUBBLE_MIN_TEXT_WIDTH_DP = 96
        private const val BUBBLE_PADDING_DP = 10
        private const val BUBBLE_CORNER_DP = 15
        private const val BUBBLE_GAP_DP = 5
        private const val BUBBLE_TAIL_DP = 7
        private const val BUBBLE_TEXT_SP = 13f

        private var running = false

        fun isRunning(): Boolean = running
        fun isEnabled(context: android.content.Context): Boolean =
            context.getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(ENABLED, false)

        fun setEnabled(context: android.content.Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .putBoolean(ENABLED, enabled)
                .apply()
        }
    }

    private lateinit var windowManager: WindowManager
    private var overlayView: KittenOverlayView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private val bubblePaint = TextPaint(Paint.ANTI_ALIAS_FLAG)

    /** The line currently shown, or null when the bubble is hidden. */
    private var bubbleText: String? = null

    /**
     * Where the cat itself sits on the screen, in pixels. This is the anchor:
     * the window grows and shrinks around it as the bubble appears, so the cat
     * never jumps when the bubble changes.
     */
    private var catLeft = 0
    private var catTop = 0

    /** The app Kitten last talked about, handed over on the next tap. */
    private var openedPackage: String? = null
    private var openedLabel: String? = null
    private var openedLine: String? = null

    /** The last app already commented on, so Kitten says it once. */
    private var lastWatchedPackage: String? = null

    private val handler = Handler(Looper.getMainLooper())
    private var pendingHide: Runnable? = null

    private val appWatcher = object : Runnable {
        override fun run() {
            if (!running) return
            watchForOpenedApp()
            handler.postDelayed(this, APP_POLL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        try {
            createNotificationChannel()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    createNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                @Suppress("DEPRECATION")
                startForeground(NOTIFICATION_ID, createNotification())
            }
            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
            bubblePaint.textSize = sp(BUBBLE_TEXT_SP)
            bubblePaint.color = Color.rgb(38, 26, 18)
            showOverlay()
            // The cat has arrived, so it says hello.
            showBubble(GREETING)
            handler.postDelayed(appWatcher, FIRST_APP_CHECK_MS)
        } catch (_: RuntimeException) {
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_NOT_STICKY

    override fun onDestroy() {
        handler.removeCallbacks(appWatcher)
        pendingHide?.let { handler.removeCallbacks(it) }
        pendingHide = null
        overlayView?.let { view ->
            runCatching { windowManager.removeView(view) }
        }
        overlayView = null
        layoutParams = null
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun showOverlay() {
        val size = dp(CAT_SIZE_DP)
        val margin = dp(INITIAL_MARGIN_DP)
        val bounds = screenBounds()
        catLeft = (bounds.width() - size - margin).coerceAtLeast(0)
        catTop = (bounds.height() / 2 - size / 2).coerceAtLeast(margin)

        val params = WindowManager.LayoutParams(
            size,
            size,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = catLeft
            y = catTop
        }

        val view = KittenOverlayView()
        overlayView = view
        layoutParams = params
        windowManager.addView(view, params)
        running = true
    }

    // ---------------------------------------------------------------- bubble

    private fun showBubble(text: String) {
        bubbleText = text
        pendingHide?.let { handler.removeCallbacks(it) }
        val hide = Runnable { clearBubble() }
        pendingHide = hide
        handler.postDelayed(hide, BUBBLE_VISIBLE_MS)
        applyLayout()
    }

    private fun clearBubble() {
        pendingHide?.let { handler.removeCallbacks(it) }
        pendingHide = null
        bubbleText = null
        applyLayout()
    }

    /** The bubble's size, given the text and the widest it may be. */
    private fun measureBubble(text: String, maxWidth: Int): Pair<Int, Int> {
        val padding = dp(BUBBLE_PADDING_DP)
        val available = (maxWidth - 2 * padding).coerceAtLeast(dp(BUBBLE_MIN_TEXT_WIDTH_DP))
        // A short line hugs its text; a long one wraps at the cap.
        val textWidth = min(available, max(ceil(bubblePaint.measureText(text)).toInt(), 1))
        val layout = bubbleLayout(text, textWidth)
        return (textWidth + 2 * padding) to (layout.height + 2 * padding)
    }

    private fun bubbleLayout(text: String, textWidth: Int): StaticLayout =
        StaticLayout.Builder.obtain(text, 0, text.length, bubblePaint, textWidth)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setMaxLines(4)
            .setEllipsize(TextUtils.TruncateAt.END)
            .build()

    /**
     * Sizes and places the overlay window for the current bubble, keeping the
     * cat exactly where it was.
     *
     * The window is only as large as it needs to be: the cat alone, or the cat
     * plus room for the bubble on whichever side has space.
     */
    private fun applyLayout() {
        val params = layoutParams ?: return
        val view = overlayView ?: return
        val bounds = screenBounds()
        val catSize = dp(CAT_SIZE_DP)
        val text = bubbleText

        val geometry = if (text == null) {
            Geometry(catSize, catSize, 0, 0, 0, 0, 0, 0, tailOnRight = false)
        } else {
            val gap = dp(BUBBLE_GAP_DP)
            val maxBubbleWidth = (bounds.width() - catSize - gap)
                .coerceAtLeast(dp(BUBBLE_MIN_TEXT_WIDTH_DP))
            val (bubbleWidth, bubbleHeight) = measureBubble(text, maxBubbleWidth)
            val width = catSize + gap + bubbleWidth
            val height = max(catSize, bubbleHeight)
            val spaceOnLeft = catLeft
            val spaceOnRight = bounds.width() - (catLeft + catSize)
            // Prefer the left so the bubble does not cover the app's own
            // controls along the right edge, unless the cat is pinned there.
            val bubbleOnLeft = spaceOnLeft >= bubbleWidth + gap ||
                spaceOnLeft >= spaceOnRight
            Geometry(
                width = width,
                height = height,
                catLeft = if (bubbleOnLeft) width - catSize else 0,
                catTop = 0,
                bubbleLeft = if (bubbleOnLeft) 0 else width - bubbleWidth,
                bubbleTop = ((catSize - bubbleHeight) / 2)
                    .coerceIn(0, (height - bubbleHeight).coerceAtLeast(0)),
                bubbleWidth = bubbleWidth,
                bubbleHeight = bubbleHeight,
                tailOnRight = bubbleOnLeft,
            )
        }

        params.width = geometry.width
        params.height = geometry.height
        val x = (catLeft - geometry.catLeft)
            .coerceIn(0, (bounds.width() - geometry.width).coerceAtLeast(0))
        val y = (catTop - geometry.catTop)
            .coerceIn(0, (bounds.height() - geometry.height).coerceAtLeast(0))
        params.x = x
        params.y = y

        // Re-anchor to the window that actually landed on screen, so dragging
        // continues from where the cat visibly is.
        catLeft = x + geometry.catLeft
        catTop = y + geometry.catTop

        view.geometry = geometry
        view.bubbleText = text
        try {
            windowManager.updateViewLayout(view, params)
        } catch (_: RuntimeException) {
            // The window was detached while it was being repositioned.
        }
        view.invalidate()
    }

    // ------------------------------------------------------------ app watch

    /**
     * Says a line when the user opens a different app.
     *
     * Only the app's name is used: Kitten never reads what is on the screen
     * unless the user asks it to with the screen-reading button.
     */
    private fun watchForOpenedApp() {
        val app = mostRecentOtherApp() ?: return
        if (app.packageName == lastWatchedPackage) return
        lastWatchedPackage = app.packageName

        // Remembered for the tap hand-off. A line is only ever said once, but
        // it stays available until the user acts on it.
        val line = lineFor(app)
        openedPackage = app.packageName
        openedLabel = app.label
        openedLine = line
        showBubble(line)
    }

    private data class WatchedApp(val packageName: String, val label: String)

    private fun mostRecentOtherApp(): WatchedApp? {
        if (!hasUsageAccess()) return null
        val usage = getSystemService(USAGE_STATS_SERVICE) as? UsageStatsManager ?: return null
        val now = System.currentTimeMillis()
        val events = try {
            usage.queryEvents(now - APP_WINDOW_MS, now)
        } catch (_: Exception) {
            return null
        } ?: return null

        var resumed: String? = null
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            @Suppress("DEPRECATION")
            val movedToForeground =
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            // Kitten itself does not count: it is usually the app on screen
            // when the user is looking at the cat.
            if (movedToForeground && event.packageName != packageName) {
                resumed = event.packageName
            }
        }

        return resumed?.let { WatchedApp(it, labelFor(it)) }
    }

    private fun lineFor(app: WatchedApp): String {
        val packageId = app.packageName.lowercase(Locale.US)
        return when {
            packageId.contains("instagram") -> "Instagram? What are we doing here?"
            packageId.contains("whatsapp") -> "WhatsApp? Who are we texting?"
            packageId.contains("youtube") -> "YouTube? Study or entertainment?"
            packageId.contains("chrome") -> "Chrome? What are we looking for?"
            packageId.contains("spotify") -> "Spotify? What are we listening to?"
            app.label.isNotBlank() -> "${app.label}? What are we doing here?"
            else -> "A new app? What are we doing here?"
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(APP_OPS_SERVICE) as? AppOpsManager ?: return false
        val mode = appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * The app's display name, or an empty string when Android withholds the
     * package. The app does not request QUERY_ALL_PACKAGES, so callers fall
     * back to a name derived from the package id.
     */
    private fun labelFor(target: String): String {
        return try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(target, 0),
            ).toString()
        } catch (_: Exception) {
            ""
        }
    }

    private fun screenBounds(): android.graphics.Rect {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            windowManager.currentWindowMetrics.bounds
        } else {
            @Suppress("DEPRECATION")
            val metrics = DisplayMetrics().also { windowManager.defaultDisplay.getMetrics(it) }
            android.graphics.Rect(0, 0, metrics.widthPixels, metrics.heightPixels)
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).roundToInt()

    private fun sp(value: Float): Float = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_SP,
        value,
        resources.displayMetrics,
    )

    // ------------------------------------------------------------ the window

    /** Where the cat and the bubble sit inside the overlay window. */
    private class Geometry(
        val width: Int,
        val height: Int,
        val catLeft: Int,
        val catTop: Int,
        val bubbleLeft: Int,
        val bubbleTop: Int,
        val bubbleWidth: Int,
        val bubbleHeight: Int,
        val tailOnRight: Boolean,
    )

    private inner class KittenOverlayView : View(this) {
        private val fur = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(240, 164, 92) }
        private val shade = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(59, 42, 30) }
        private val nose = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(229, 139, 160) }
        private val bubbleFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(240, 255, 248, 238)
        }
        private val bubbleEdge = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(90, 120, 86, 52)
            style = Paint.Style.STROKE
            strokeWidth = 1.5f * resources.displayMetrics.density
        }
        private val bubbleTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(38, 26, 18)
            textSize = sp(BUBBLE_TEXT_SP)
        }
        private val touchSlop =
            ViewConfiguration.get(this@FloatingKittenService).scaledTouchSlop

        var geometry: Geometry? = null
        var bubbleText: String? = null

        private var downX = 0f
        private var downY = 0f
        private var startCatLeft = 0
        private var startCatTop = 0
        private var moved = false

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val layout = geometry ?: return
            drawBubble(canvas, layout)
            canvas.save()
            canvas.translate(layout.catLeft.toFloat(), layout.catTop.toFloat())
            drawKitten(canvas, dp(CAT_SIZE_DP).toFloat())
            canvas.restore()
        }

        private fun drawBubble(canvas: Canvas, layout: Geometry) {
            val text = bubbleText ?: return
            if (layout.bubbleWidth <= 0 || layout.bubbleHeight <= 0) return

            val rect = RectF(
                layout.bubbleLeft.toFloat(),
                layout.bubbleTop.toFloat(),
                (layout.bubbleLeft + layout.bubbleWidth).toFloat(),
                (layout.bubbleTop + layout.bubbleHeight).toFloat(),
            )
            val radius = dp(BUBBLE_CORNER_DP).toFloat()
            canvas.drawRoundRect(rect, radius, radius, bubbleFill)
            canvas.drawRoundRect(rect, radius, radius, bubbleEdge)

            // A small tail pointing back at the cat, so the line reads as
            // something Kitten just said.
            val tail = dp(BUBBLE_TAIL_DP).toFloat()
            val centerY = rect.centerY()
            val tailPath = Path()
            if (layout.tailOnRight) {
                tailPath.moveTo(rect.right - 1f, centerY - tail)
                tailPath.lineTo(rect.right + tail * 1.7f, centerY)
                tailPath.lineTo(rect.right - 1f, centerY + tail)
            } else {
                tailPath.moveTo(rect.left + 1f, centerY - tail)
                tailPath.lineTo(rect.left - tail * 1.7f, centerY)
                tailPath.lineTo(rect.left + 1f, centerY + tail)
            }
            tailPath.close()
            canvas.drawPath(tailPath, bubbleFill)

            val padding = dp(BUBBLE_PADDING_DP)
            val textWidth = (layout.bubbleWidth - 2 * padding).coerceAtLeast(1)
            val textLayout =
                StaticLayout.Builder.obtain(text, 0, text.length, bubbleTextPaint, textWidth)
                    .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                    .setMaxLines(4)
                    .setEllipsize(TextUtils.TruncateAt.END)
                    .build()
            canvas.save()
            canvas.translate(
                (layout.bubbleLeft + padding).toFloat(),
                (layout.bubbleTop + padding).toFloat(),
            )
            textLayout.draw(canvas)
            canvas.restore()
        }

        private fun drawKitten(canvas: Canvas, size: Float) {
            val centerX = size / 2f
            val centerY = size / 2f
            val radius = size * 0.38f
            canvas.drawCircle(centerX, centerY, size * 0.48f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(220, 255, 224, 190)
            })

            val leftEar = Path().apply {
                moveTo(centerX - radius * 0.78f, centerY - radius * 0.45f)
                lineTo(centerX - radius * 0.55f, centerY - radius * 1.22f)
                lineTo(centerX - radius * 0.08f, centerY - radius * 0.62f)
                close()
            }
            canvas.drawPath(leftEar, fur)
            val rightEar = Path().apply {
                moveTo(centerX + radius * 0.78f, centerY - radius * 0.45f)
                lineTo(centerX + radius * 0.55f, centerY - radius * 1.22f)
                lineTo(centerX + radius * 0.08f, centerY - radius * 0.62f)
                close()
            }
            canvas.drawPath(rightEar, fur)
            canvas.drawCircle(centerX, centerY, radius, fur)

            val eyeRadius = radius * 0.105f
            canvas.drawCircle(centerX - radius * 0.36f, centerY - radius * 0.08f, eyeRadius, shade)
            canvas.drawCircle(centerX + radius * 0.36f, centerY - radius * 0.08f, eyeRadius, shade)
            val highlight = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
            canvas.drawCircle(centerX - radius * 0.36f, centerY - radius * 0.12f, eyeRadius * 0.3f, highlight)
            canvas.drawCircle(centerX + radius * 0.36f, centerY - radius * 0.12f, eyeRadius * 0.3f, highlight)
            canvas.drawOval(
                RectF(
                    centerX - radius * 0.12f,
                    centerY + radius * 0.04f,
                    centerX + radius * 0.12f,
                    centerY + radius * 0.18f,
                ),
                nose,
            )
            canvas.drawArc(
                RectF(centerX - radius * 0.22f, centerY + radius * 0.12f, centerX, centerY + radius * 0.34f),
                0f,
                75f,
                false,
                shade,
            )
            canvas.drawArc(
                RectF(centerX, centerY + radius * 0.12f, centerX + radius * 0.22f, centerY + radius * 0.34f),
                105f,
                75f,
                false,
                shade,
            )
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (layoutParams == null) return false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startCatLeft = catLeft
                    startCatTop = catTop
                    moved = false
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (abs(dx) > touchSlop || abs(dy) > touchSlop) moved = true
                    val catSize = dp(CAT_SIZE_DP)
                    val bounds = screenBounds()
                    catLeft = (startCatLeft + dx.roundToInt())
                        .coerceIn(0, (bounds.width() - catSize).coerceAtLeast(0))
                    catTop = (startCatTop + dy.roundToInt())
                        .coerceIn(0, (bounds.height() - catSize).coerceAtLeast(0))
                    applyLayout()
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        clearBubble()
                        openMainActivity()
                    }
                    return true
                }
            }
            return true
        }

        /** Opens Kitten, telling it which app the user was just in. */
        private fun openMainActivity() {
            val intent = Intent(this@FloatingKittenService, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                openedPackage?.let { opened ->
                    putExtra(MainActivity.EXTRA_APP_CONTEXT_PACKAGE, opened)
                    putExtra(MainActivity.EXTRA_APP_CONTEXT_LABEL, openedLabel ?: "")
                    putExtra(MainActivity.EXTRA_APP_CONTEXT_LINE, openedLine ?: "")
                }
            }
            // The hand-off is one-shot: the next tap starts from whatever app
            // is open then.
            openedPackage = null
            openedLabel = null
            openedLine = null
            startActivity(intent)
        }
    }

    // -------------------------------------------------------- the notification

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Floating Kitten",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps the user-started Floating Kitten available."
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            7402,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Floating Kitten is on")
                .setContentText("Tap the kitten to open Kitten AI.")
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Floating Kitten is on")
                .setContentText("Tap the kitten to open Kitten AI.")
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }
}
