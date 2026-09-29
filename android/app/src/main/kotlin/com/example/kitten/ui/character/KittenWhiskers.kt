package com.example.kitten.ui.character

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope

private val WhiskerColor = Color(0x6678350F)

/**
 * Native vector kitten whiskers rendered on left and right sides of the cheeks.
 */
@Composable
fun KittenWhiskers(
    modifier: Modifier = Modifier
) {
    Canvas(modifier = modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height

        val strokeWidth = (w * 0.015f).coerceAtLeast(1.5f)
        val whiskerLen = w * 0.16f

        // --- Left Whiskers ---
        val leftStartX = w * 0.18f
        val leftStartY = h * 0.62f
        // Top left whisker (angled slightly downward)
        drawLine(
            color = WhiskerColor,
            start = Offset(leftStartX, leftStartY - h * 0.025f),
            end = Offset(leftStartX - whiskerLen, leftStartY - h * 0.045f),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )
        // Bottom left whisker (angled slightly upward)
        drawLine(
            color = WhiskerColor,
            start = Offset(leftStartX, leftStartY + h * 0.025f),
            end = Offset(leftStartX - whiskerLen * 1.1f, leftStartY + h * 0.045f),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )

        // --- Right Whiskers ---
        val rightStartX = w * 0.82f
        val rightStartY = h * 0.62f
        // Top right whisker
        drawLine(
            color = WhiskerColor,
            start = Offset(rightStartX, rightStartY - h * 0.025f),
            end = Offset(rightStartX + whiskerLen, rightStartY - h * 0.045f),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )
        // Bottom right whisker
        drawLine(
            color = WhiskerColor,
            start = Offset(rightStartX, rightStartY + h * 0.025f),
            end = Offset(rightStartX + whiskerLen * 1.1f, rightStartY + h * 0.045f),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )
    }
}
