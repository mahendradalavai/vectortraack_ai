package com.example.kitten.ui.character

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke

private val PawColor = Color(0xFFEA580C)
private val PawBorder = Color(0x80C2410C)

/**
 * Native vector kitten paws. In [KittenState.WALKING], the paws alternately bounce
 * up and down in a natural walking cadence.
 */
@Composable
fun KittenPaws(
    state: KittenState,
    modifier: Modifier = Modifier
) {
    val isWalking = state == KittenState.WALKING

    val infiniteTransition = rememberInfiniteTransition(label = "pawWalking")
    val leftPawBounce by infiniteTransition.animateFloat(
        initialValue = -1f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 280, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "leftPawBounce"
    )

    Canvas(modifier = modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height

        val pawWidth = w * 0.20f
        val pawHeight = h * 0.12f
        val pawBottomY = h * 0.94f

        val bounceAmount = if (isWalking) (h * 0.04f) else 0f
        val leftBounce = bounceAmount * leftPawBounce
        val rightBounce = -bounceAmount * leftPawBounce

        val pawSpacing = w * 0.24f
        val leftPawX = (w / 2) - (pawSpacing / 2) - (pawWidth / 2)
        val rightPawX = (w / 2) + (pawSpacing / 2) - (pawWidth / 2)

        // Draw left paw
        drawPaw(
            x = leftPawX,
            y = pawBottomY - pawHeight + leftBounce,
            width = pawWidth,
            height = pawHeight
        )

        // Draw right paw
        drawPaw(
            x = rightPawX,
            y = pawBottomY - pawHeight + rightBounce,
            width = pawWidth,
            height = pawHeight
        )
    }
}

private fun DrawScope.drawPaw(
    x: Float,
    y: Float,
    width: Float,
    height: Float
) {
    val cornerRadius = CornerRadius(width / 2, height / 2)
    // Paw body
    drawRoundRect(
        color = PawColor,
        topLeft = Offset(x, y),
        size = Size(width, height),
        cornerRadius = cornerRadius
    )
    // Paw outline
    drawRoundRect(
        color = PawBorder,
        topLeft = Offset(x, y),
        size = Size(width, height),
        cornerRadius = cornerRadius,
        style = Stroke(width = 1.5f)
    )
}
