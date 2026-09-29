package com.example.kitten.ui.character

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate

private val EarOrange = Color(0xFFF97316)
private val EarBorder = Color(0x66EA580C)
private val EarInnerPink = Color(0xFFFECDD3)

/**
 * Native vector kitten ears. In [KittenState.LISTENING], ears perk upward
 * and rotate to an attentive angle.
 */
@Composable
fun KittenEars(
    state: KittenState,
    modifier: Modifier = Modifier
) {
    val isListening = state == KittenState.LISTENING

    // Ear rotation: default -25°/25°, perked -12°/12° when listening
    val leftEarRotation by animateFloatAsState(
        targetValue = if (isListening) -12f else -25f,
        animationSpec = tween(durationMillis = 300),
        label = "leftEarRotation"
    )
    val rightEarRotation by animateFloatAsState(
        targetValue = if (isListening) 12f else 25f,
        animationSpec = tween(durationMillis = 300),
        label = "rightEarRotation"
    )
    val earTranslateY by animateFloatAsState(
        targetValue = if (isListening) -0.04f else 0f,
        animationSpec = tween(durationMillis = 300),
        label = "earTranslateY"
    )

    Canvas(modifier = modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height

        // Ear size proportional to overall kitten size (approx 28dp on 80dp)
        val earW = w * 0.35f
        val earH = h * 0.35f
        val yShift = earTranslateY * h

        // --- Left Ear ---
        val leftEarCenterX = w * 0.22f
        val leftEarCenterY = h * 0.22f + yShift
        rotate(degrees = leftEarRotation, pivot = Offset(leftEarCenterX, leftEarCenterY)) {
            translate(left = leftEarCenterX - earW / 2, top = leftEarCenterY - earH / 2) {
                drawRoundedEar(
                    width = earW,
                    height = earH,
                    isLeft = true
                )
            }
        }

        // --- Right Ear ---
        val rightEarCenterX = w * 0.78f
        val rightEarCenterY = h * 0.22f + yShift
        rotate(degrees = rightEarRotation, pivot = Offset(rightEarCenterX, rightEarCenterY)) {
            translate(left = rightEarCenterX - earW / 2, top = rightEarCenterY - earH / 2) {
                drawRoundedEar(
                    width = earW,
                    height = earH,
                    isLeft = false
                )
            }
        }
    }
}

private fun DrawScope.drawRoundedEar(
    width: Float,
    height: Float,
    isLeft: Boolean
) {
    val path = Path().apply {
        val cornerLarge = CornerRadius(width * 0.42f, height * 0.42f)
        val cornerSmall = CornerRadius(width * 0.18f, height * 0.18f)

        val tl = if (isLeft) cornerLarge else cornerSmall
        val tr = if (isLeft) cornerSmall else cornerLarge
        addRoundRect(
            RoundRect(
                left = 0f,
                top = 0f,
                right = width,
                bottom = height,
                topLeftCornerRadius = tl,
                topRightCornerRadius = tr,
                bottomLeftCornerRadius = cornerSmall,
                bottomRightCornerRadius = cornerSmall
            )
        )
    }

    // Outer ear fill & border
    drawPath(path = path, color = EarOrange)
    drawPath(path = path, color = EarBorder, style = Stroke(width = 1.5f))

    // Inner pink ear pad
    val innerInsetX = width * 0.20f
    val innerInsetY = height * 0.20f
    val innerW = width - (innerInsetX * 2)
    val innerH = height - (innerInsetY * 2)

    val innerPath = Path().apply {
        val innerCornerLarge = CornerRadius(innerW * 0.40f, innerH * 0.40f)
        val innerCornerSmall = CornerRadius(innerW * 0.16f, innerH * 0.16f)
        val innerTl = if (isLeft) innerCornerLarge else innerCornerSmall
        val innerTr = if (isLeft) innerCornerSmall else innerCornerLarge

        addRoundRect(
            RoundRect(
                left = innerInsetX,
                top = innerInsetY,
                right = innerInsetX + innerW,
                bottom = innerInsetY + innerH,
                topLeftCornerRadius = innerTl,
                topRightCornerRadius = innerTr,
                bottomLeftCornerRadius = innerCornerSmall,
                bottomRightCornerRadius = innerCornerSmall
            )
        )
    }
    drawPath(path = innerPath, color = EarInnerPink)
}
