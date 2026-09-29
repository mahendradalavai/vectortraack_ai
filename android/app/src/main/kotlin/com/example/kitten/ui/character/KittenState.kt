package com.example.kitten.ui.character

import java.util.Locale

/**
 * Represents the animation and emotional state of the Floating Kitten character.
 *
 * Designed to support immediate animation states as well as upcoming AI-driven
 * emotional expressions from Gemini responses.
 */
enum class KittenState {
    // Primary / Required animation states
    IDLE,
    BLINKING,
    SLEEPING,
    LOOKING,
    WALKING,
    LISTENING,

    // Extended emotional expressions prepared for Gemini AI integration
    HAPPY,
    SAD,
    SURPRISED,
    ANGRY,
    CONFUSED,
    EXCITED,
    LOVE,
    THINKING,
    CURIOUS;

    companion object {
        /**
         * Safely maps an incoming string (e.g., from Gemini JSON payload)
         * to a predefined [KittenState]. Defaults safely to [IDLE] to prevent
         * arbitrary code or unrecognized states from breaking the UI.
         */
        fun fromString(value: String?): KittenState {
            if (value.isNullOrBlank()) return IDLE
            val normalized = value.trim().uppercase(Locale.ROOT)
            return entries.firstOrNull { it.name == normalized } ?: IDLE
        }
    }
}
