package com.example.kitten

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import java.util.Locale

/**
 * Opt-in foreground listener for the Hey Kitty wake phrase.
 *
 * This service owns the microphone only: it spots the wake phrase, speaks a
 * short acknowledgement, and hands the rest of the sentence to the app for a
 * normal, confirmation-safe turn. Lines about the app the user just opened
 * belong to [FloatingKittenService], which shows them whether or not the
 * microphone is on, so nothing is announced twice.
 */
class BackgroundAssistantService : Service(), RecognitionListener {

    companion object {
        private const val CHANNEL_ID = "kitten_background_assistant"
        private const val NOTIFICATION_ID = 7403
        private const val PREFS = "kitten_background_assistant"
        private const val ENABLED = "enabled"
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

    private var recognizer: SpeechRecognizer? = null
    private var textToSpeech: TextToSpeech? = null
    private var restarting = false
    private var lastHandledCommand: String? = null
    private var lastHandledAt = 0L

    override fun onCreate() {
        super.onCreate()
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED ||
            !SpeechRecognizer.isRecognitionAvailable(this)
        ) {
            stopSelf()
            return
        }
        try {
            createNotificationChannel()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification(),
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                @Suppress("DEPRECATION")
                startForeground(NOTIFICATION_ID, notification())
            }
            textToSpeech = TextToSpeech(this) { status ->
                if (status == TextToSpeech.SUCCESS) textToSpeech?.language = Locale.US
            }
            recognizer = SpeechRecognizer.createSpeechRecognizer(this).also {
                it.setRecognitionListener(this)
            }
            running = true
            listen()
        } catch (_: RuntimeException) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        recognizer?.destroy()
        recognizer = null
        textToSpeech?.shutdown()
        textToSpeech = null
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_NOT_STICKY

    private fun listen() {
        if (!running || restarting) return
        restarting = true
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.US)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        }
        try {
            recognizer?.startListening(intent)
        } catch (_: RuntimeException) {
            scheduleListen()
        }
    }

    private fun scheduleListen() {
        restarting = false
        if (running) android.os.Handler(mainLooper).postDelayed({ listen() }, 900)
    }

    private fun handleText(text: String) {
        val normalized = text.trim().lowercase(Locale.US)
        val wakeIndex = listOf("hey kitty", "kitty").firstNotNullOfOrNull { phrase ->
            normalized.indexOf(phrase).takeIf { it >= 0 }?.let { it to phrase.length }
        } ?: return
        val command = normalized.substring(wakeIndex.first + wakeIndex.second).trim(' ', ',', '.', ':')
        if (command.isEmpty()) {
            speak("Yes? What should we do?")
            return
        }
        val now = System.currentTimeMillis()
        if (command == lastHandledCommand && now - lastHandledAt < 4000) return
        lastHandledCommand = command
        lastHandledAt = now
        speak("Opening Kitten for that.")
        startActivity(Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_ASSISTANT_COMMAND, command)
        })
    }

    private fun speak(text: String) {
        textToSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "kitten_background")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Kitten background listening",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Shows when Kitten is listening for Hey Kitty." },
        )
    }

    private fun notification(): Notification {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Kitten is listening")
                .setContentText("Say Hey Kitty to open a voice command.")
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Kitten is listening")
                .setContentText("Say Hey Kitty to open a voice command.")
                .setOngoing(true)
                .build()
        }
    }

    override fun onReadyForSpeech(params: Bundle?) { restarting = false }
    override fun onBeginningOfSpeech() = Unit
    override fun onRmsChanged(rmsdB: Float) = Unit
    override fun onBufferReceived(buffer: ByteArray?) = Unit
    override fun onEndOfSpeech() = scheduleListen()
    override fun onError(error: Int) = scheduleListen()
    override fun onResults(results: Bundle?) {
        results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            ?.let(::handleText)
        scheduleListen()
    }
    override fun onPartialResults(partialResults: Bundle?) {
        partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            ?.let(::handleText)
    }
    override fun onEvent(eventType: Int, params: Bundle?) = Unit
}
