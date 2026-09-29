package com.example.kitten.ui.character

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
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
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke

private val EyeDark = Color(0xFF171717)
private val EyeBlinkLine = Color(0xFF451A03)
private val EyeHighlight = Color.White

/**
 * Native vector kitten eyes. Handles open cute oval eyes with highlight,
 * smooth horizontal line blinking, sleeping closed eyes, and looking shifts.
 */
@Composable
fun KittenEyes(
    isBlinking: Boolean,
    state: KittenState,
    lookProgress: Float = 0f, // -1f (left) to +1f (right)
    modifier: Modifier = Modifier
) {
    val isClosed = isBlinking || state == KittenState.SLEEPING || state == KittenState.BLINKING
    val isHappy = state == KittenState.HAPPY

    // Smooth transition between open height and closed line height
    val eyeHeightFactor by animateFloatAsState(
        targetValue = if (isClosed) 0.12f else 1f,
        animationSpec = tween(durationMillis = if (isBlinking) 100 else 200),
        label = "eyeHeightFactor"
    )

    Canvas(modifier = modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height

        // Eyes position row inside the face (around 46% - 50% vertical center)
        val eyeRowY = h * 0.49f
        val eyeSpacing = w * 0.28f
        val leftEyeCenterX = (w / 2) - (eyeSpacing / 2) + (lookProgress * w * 0.03f)
        val rightEyeCenterX = (w / 2) + (eyeSpacing / 2) + (lookProgress * w * 0.03f)

        val eyeWidth = w * 0.125f
        val fullEyeHeight = h * 0.15f
        val currentEyeHeight = fullEyeHeight * eyeHeightFactor

        if (isHappy && !isClosed) {
            // Cute happy arched eyes "^ ^"
            drawHappyEye(leftEyeCenterX, eyeRowY, eyeWidth)
            drawHappyEye(rightEyeCenterX, eyeRowY, eyeWidth)
        } else if (isClosed) {
            // Closed / blinking line: horizontal rounded slit
            drawClosedEye(leftEyeCenterX, eyeRowY, eyeWidth)
            drawClosedEye(rightEyeCenterX, eyeRowY, eyeWidth)
        } else {
            // Normal open cute eyes with white sparkle highlight
            drawOpenEye(
                centerX = leftEyeCenterX,
                centerY = eyeRowY,
                width = eyeWidth,
                height = currentEyeHeight
            )
            drawOpenEye(
                centerX = rightEyeCenterX,
                centerY = eyeRowY,
                width = eyeWidth,
                height = currentEyeHeight
            )
        }
    }
}

private fun DrawScope.drawOpenEye(
    centerX: Float,
    centerY: Float,
    width: Float,
    height: Float
) {
    val left = centerX - (width / 2)
    val top = centerY - (height / 2)

    // Dark vertical oval eye
    drawRoundRect(
        color = EyeDark,
        topLeft = Offset(left, top),
        size = Size(width, height),
        cornerRadius = CornerRadius(width / 2, height / 2)
    )

    // White eye highlight dot in upper-right corner
    val highlightSize = width * 0.38f
    val highlightX = left + width * 0.65f
    val highlightY = top + height * 0.28f
    drawCircle(
        color = EyeHighlight,
        radius = highlightSize / 2,
        center = Offset(highlightX, highlightY)
    )
}

private fun DrawScope.drawClosedEye(
    centerX: Float,
    centerY: Float,
    width: Float
) {
    val halfW = width * 0.55f
    val path = Path().apply {
        moveTo(centerX - halfW, centerY)
        // Gentle downward sleep arc
        quadraticTo(
            centerX, centerY + (width * 0.18f),
            centerX + halfW, centerY
        )
    }
    drawPath(
        path = path,
        color = EyeBlinkLine,
        style = Stroke(
            width = width * 0.28f,
            cap = StrokeCap.Round
        )
    )
}

private fun DrawScope.drawHappyEye(
    centerX: Float,
    centerY: Float,
    width: Float
) {
    val halfW = width * 0.55f
    val path = Path().apply {
        moveTo(centerX - halfW, centerY + (width * 0.2f))
        // Upward arched happy eye "^"
        quadraticTo(
            centerX, centerY - (width * 0.35f),
            centerX + halfW, centerY + (width * 0.2f)
        )
    }
    drawPath(
        path = path,
        color = EyeDark,
        style = Stroke(
            width = width * 0.28f,
            cap = StrokeCap.Round
        )
    )
}
