package com.example.kitten.ui.character

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Central controller for managing the kitten's animation state, emotions,
 * dialogue bubbles, and interactions.
 *
 * Can be controlled programmatically, by user gestures, or by future
 * Gemini AI assistant responses.
 */
class KittenAnimationController(
    initialState: KittenState = KittenState.IDLE,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())
) {
    var state: KittenState by mutableStateOf(initialState)

    var dialogue: String? by mutableStateOf(null)

    var isDragging: Boolean by mutableStateOf(false)

    private var dialogueJob: Job? = null

    /**
     * Safely updates the kitten's state from a string identifier (e.g. from
     * Gemini JSON `{ "expression": "HAPPY" }`).
     */
    fun setState(stateName: String?) {
        state = KittenState.fromString(stateName)
    }

    /**
     * Shows a speech bubble with the given [text] for [durationMs] milliseconds.
     * When [durationMs] <= 0, the bubble remains until explicitly cleared.
     */
    fun setDialogue(text: String?, durationMs: Long = 6500L) {
        dialogueJob?.cancel()
        dialogue = text
        if (!text.isNullOrBlank() && durationMs > 0) {
            dialogueJob = scope.launch {
                delay(durationMs)
                dialogue = null
            }
        }
    }

    fun clearDialogue() {
        dialogueJob?.cancel()
        dialogue = null
    }
}
