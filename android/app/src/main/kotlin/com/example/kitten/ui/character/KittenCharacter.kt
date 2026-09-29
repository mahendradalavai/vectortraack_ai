package com.example.kitten.ui.character

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlin.random.Random

/**
 * Native Jetpack Compose Floating Kitten Character.
 *
 * Rendered 100% using native vector drawing (Compose Canvas, DrawScope,
 * paths, gradients, and Compose animations). No raster images or WebViews.
 *
 * @param state Current [KittenState] (IDLE, BLINKING, SLEEPING, LOOKING, WALKING, LISTENING, etc.)
 * @param dialogue Optional text to display inside the speech bubble above kitten's head.
 * @param isDragging Whether the character is currently being dragged.
 * @param size Configurable dimension for the kitten character (default: 80.dp).
 * @param onTap Callback invoked when the kitten is tapped.
 */
@Composable
fun FloatingKittenCharacter(
    state: KittenState = KittenState.IDLE,
    dialogue: String? = null,
    isDragging: Boolean = false,
    size: Dp = 80.dp,
    onTap: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    // --- Natural Blinking Loop (every 3–5 seconds) ---
    var naturalBlink by remember { mutableStateOf(false) }

    LaunchedEffect(state) {
        if (state == KittenState.SLEEPING) return@LaunchedEffect
        while (true) {
            // Randomized idle blink interval between 3200ms and 4800ms
            val nextInterval = Random.nextLong(3200L, 4800L)
            delay(nextInterval)
            naturalBlink = true
            val blinkDuration = Random.nextLong(160L, 240L)
            delay(blinkDuration)
            naturalBlink = false
        }
    }

    val isBlinking = naturalBlink || state == KittenState.BLINKING || state == KittenState.SLEEPING

    // --- Infinite Transitions for Breathing, Looking, and Walking ---
    val infiniteTransition = rememberInfiniteTransition(label = "kittenIdleMovement")

    // Subtle breathing scale: 1f -> 1.03f during IDLE
    val breathingScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.03f,
        animationSpec = infiniteRepeatable(
            animation = tween(
                durationMillis = if (state == KittenState.SLEEPING) 3600 else 1400,
                easing = FastOutSlowInEasing
            ),
            repeatMode = RepeatMode.Reverse
        ),
        label = "breathingScale"
    )

    // Subtle idle body rotation (-1° to 1°)
    val idleRotation by infiniteTransition.animateFloat(
        initialValue = -1f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1400, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "idleRotation"
    )

    // Looking head rotation (-8° to 8°)
    val lookingRotation by infiniteTransition.animateFloat(
        initialValue = -8f,
        targetValue = 8f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1200, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "lookingRotation"
    )

    // Walking body tilt (-3° to 3°)
    val walkingRotation by infiniteTransition.animateFloat(
        initialValue = -3f,
        targetValue = 3f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 300, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "walkingRotation"
    )

    // Target scale based on state & dragging
    val baseScale = when {
        isDragging -> 1.08f
        state == KittenState.SLEEPING -> 0.94f
        else -> breathingScale
    }
    val animatedScale by animateFloatAsState(
        targetValue = baseScale,
        animationSpec = spring(),
        label = "kittenAnimatedScale"
    )

    // Current rotation angle based on state
    val targetRotation = when {
        isDragging -> 5f
        state == KittenState.LOOKING -> lookingRotation
        state == KittenState.WALKING -> walkingRotation
        state == KittenState.SLEEPING -> 0f
        else -> idleRotation
    }

    val interactionSource = remember { MutableInteractionSource() }

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
    ) {
        // Speech Bubble placed above the kitten head
        KittenSpeechBubble(dialogue = dialogue)

        // Animated Kitten Root Box
        Box(
            modifier = Modifier
                .size(size)
                .graphicsLayer {
                    scaleX = animatedScale
                    scaleY = animatedScale
                    rotationZ = targetRotation
                }
                .clickable(
                    interactionSource = interactionSource,
                    indication = null
                ) {
                    onTap?.invoke()
                },
            contentAlignment = Alignment.Center
        ) {
            // 1. Kitten Ears (Background layer of the head)
            KittenEars(
                state = state,
                modifier = Modifier.size(size)
            )

            // 2. Kitten Body, Head Gradient, Cheeks, Nose, Mouth & Pulse Rings
            KittenBody(
                state = state,
                isDragging = isDragging,
                modifier = Modifier.size(size)
            )

            // 3. Whiskers on Cheeks
            KittenWhiskers(
                modifier = Modifier.size(size)
            )

            // 4. Kitten Eyes (Open, Blinking, Sleeping, Looking)
            val lookProgress = if (state == KittenState.LOOKING) (lookingRotation / 8f) else 0f
            KittenEyes(
                isBlinking = isBlinking,
                state = state,
                lookProgress = lookProgress,
                modifier = Modifier.size(size)
            )

            // 5. Kitten Paws (Bottom layer with walking animation)
            KittenPaws(
                state = state,
                modifier = Modifier.size(size)
            )
        }
    }
}
