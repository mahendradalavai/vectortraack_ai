package com.example.kitten

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import java.io.ByteArrayOutputStream

/**
 * Takes one screenshot through the MediaProjection grant handed over by
 * [MainActivity], then stops.
 *
 * Android requires the projection to be obtained by a foreground service of
 * the mediaProjection type, so the service exists for the few seconds a
 * capture takes and is gone immediately after. A capture of Kitten's own UI
 * is refused: the only interesting screen is the one the user was looking at
 * before they asked.
 */
class ScreenCaptureService : Service() {

    companion object {
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"

        private const val CHANNEL_ID = "screen_capture"
        private const val NOTIFICATION_ID = 40218
        private const val TAG = "KittenCapture"

        /** A real capture lands in well under a second, so this is generous. */
        private const val CAPTURE_TIMEOUT_MS = 5000L

        /**
         * Set by [MainActivity] just before the service starts, so the result
         * can be handed back to the Dart side that is awaiting it.
         */
        @Volatile
        var onCaptured: ((ByteArray?) -> Unit)? = null
    }

    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var captureThread: HandlerThread? = null

    /** Guards against finishing twice, including re-entrantly from onStop. */
    @Volatile
    private var finished = false

    /** Channel results must be delivered on the platform main thread. */
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Android refuses to start a capture until a callback is registered, and
     * uses it to tell us when the projection ends.
     */
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            finish(null)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        if (intent == null) {
            finish(null)
            return START_NOT_STICKY
        }

        startInForeground()

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Int.MIN_VALUE)
        val resultData = intent.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
        if (resultData == null) {
            finish(null)
            return START_NOT_STICKY
        }

        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
            as? MediaProjectionManager
        if (manager == null) {
            finish(null)
            return START_NOT_STICKY
        }

        try {
            val activeProjection = manager.getMediaProjection(resultCode, resultData)
            if (activeProjection == null) {
                finish(null)
                return START_NOT_STICKY
            }
            activeProjection.registerCallback(projectionCallback, mainHandler)
            projection = activeProjection
        } catch (error: Exception) {
            finish(null)
            return START_NOT_STICKY
        }

        // A failure here must never take the app down with it: the service is
        // disposable, the conversation is not.
        try {
            captureOnce()
        } catch (error: Exception) {
            Log.w(TAG, "Starting the capture failed", error)
            finish(null)
        }
        return START_NOT_STICKY
    }

    /** Shows the system's "capturing the screen" notice for the capture. */
    private fun startInForeground() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager != null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Screen capture",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("Kitten is reading your screen")
            .setContentText("One screenshot is being taken.")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun captureOnce() {
        val metrics = getScreenMetrics()
        val width = metrics.widthPixels
        val height = metrics.heightPixels

        captureThread = HandlerThread("kitten-capture").also { it.start() }
        val handler = Handler(captureThread!!.looper)

        val reader = ImageReader.newInstance(
            width,
            height,
            PixelFormat.RGBA_8888,
            2
        )
        imageReader = reader

        val virtualDisplay = projection!!.createVirtualDisplay(
            "kitten-capture",
            width,
            height,
            metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            handler
        )
        display = virtualDisplay
        Log.i(TAG, "Virtual display started at ${width}x$height")

        var settled = false
        reader.setOnImageAvailableListener({ activeReader ->
            if (settled) return@setOnImageAvailableListener

            val image = try {
                activeReader.acquireLatestImage()
            } catch (error: Exception) {
                Log.w(TAG, "Could not acquire an image", error)
                null
            }

            // The callback can fire before a frame is actually readable, so
            // wait for the next one instead of giving up on the first miss.
            if (image == null) return@setOnImageAvailableListener

            settled = true
            val bytes = try {
                imageToJpeg(image)
            } catch (error: Exception) {
                Log.w(TAG, "Could not encode the screenshot", error)
                null
            } finally {
                image.close()
            }

            finish(bytes)
        }, handler)

        // A mirrored display produces its first frame almost immediately, but
        // not synchronously, so give up rather than hang if it never arrives.
        handler.postDelayed({
            if (!settled) {
                Log.w(TAG, "No frame arrived within ${CAPTURE_TIMEOUT_MS}ms")
                settled = true
                finish(null)
            }
        }, CAPTURE_TIMEOUT_MS)
    }

    /**
     * The current screen size and density.
     *
     * Density comes from resources because it is always populated, and the
     * projection refuses to start without a positive one. Size prefers the
     * window metrics, which stay correct on displays the activity does not own.
     */
    private fun getScreenMetrics(): DisplayMetrics {
        val metrics = DisplayMetrics()
        val base = resources.displayMetrics
        metrics.densityDpi = base.densityDpi
        metrics.widthPixels = base.widthPixels
        metrics.heightPixels = base.heightPixels

        val windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        if (windowManager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            if (bounds.width() > 0 && bounds.height() > 0) {
                metrics.widthPixels = bounds.width()
                metrics.heightPixels = bounds.height()
            }
        }

        if (metrics.densityDpi <= 0) {
            metrics.densityDpi = DisplayMetrics.DENSITY_DEFAULT
        }
        return metrics
    }

    /** Downscales to at most 1080 pixels wide and compresses to JPEG. */
    private fun imageToJpeg(image: android.media.Image): ByteArray {
        val plane = image.planes[0]
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val bitmapWidth = rowStride / pixelStride

        val raw = Bitmap.createBitmap(
            bitmapWidth,
            image.height,
            Bitmap.Config.ARGB_8888
        )
        raw.copyPixelsFromBuffer(plane.buffer)
        // The buffer is wider than the image when the row stride is padded.
        val bitmap = if (bitmapWidth > image.width) {
            Bitmap.createBitmap(raw, 0, 0, image.width, image.height)
        } else {
            raw
        }

        val scale = if (bitmap.width > 1080) 1080f / bitmap.width else 1f
        val scaled = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * scale).toInt(),
                (bitmap.height * scale).toInt(),
                true
            ).also { if (it !== bitmap) bitmap.recycle() }
        } else {
            bitmap
        }

        val output = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 80, output)
        scaled.recycle()
        return output.toByteArray()
    }

    private fun finish(captured: ByteArray?) {
        if (finished) return
        finished = true

        val callback = onCaptured
        onCaptured = null

        try {
            display?.release()
        } catch (error: Exception) {
            // Best effort; the service is going away regardless.
        }
        try {
            imageReader?.close()
        } catch (error: Exception) {
            // Same.
        }
        try {
            projection?.stop()
        } catch (error: Exception) {
            // Same.
        }
        display = null
        imageReader = null
        projection = null

        captureThread?.quitSafely()
        captureThread = null

        callback?.let { mainHandler.post { it(captured) } }
        stopSelf()
    }

    override fun onDestroy() {
        // Safety net if the system kills the service before a capture lands.
        if (onCaptured != null) {
            finish(null)
        }
        super.onDestroy()
    }
}
