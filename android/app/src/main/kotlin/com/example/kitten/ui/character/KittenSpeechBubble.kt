package com.example.kitten.ui.character

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val BubbleBackground = Color(0xFF171717)
private val BubbleBorder = Color(0x99525252)

/**
 * Native vector speech bubble that appears above the kitten head with
 * smooth entrance/exit animations and a triangular tail pointing down.
 */
@Composable
fun KittenSpeechBubble(
    dialogue: String?,
    modifier: Modifier = Modifier
) {
    AnimatedVisibility(
        visible = !dialogue.isNullOrBlank(),
        enter = fadeIn(animationSpec = spring(stiffness = Spring.StiffnessMediumLow)) +
            scaleIn(initialScale = 0.88f) +
            slideInVertically(initialOffsetY = { 16 }),
        exit = fadeOut(animationSpec = spring(stiffness = Spring.StiffnessMediumLow)) +
            scaleOut(targetScale = 0.88f) +
            slideOutVertically(targetOffsetY = { -12 }),
        modifier = modifier
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(bottom = 6.dp)
        ) {
            Box(
                modifier = Modifier
                    .widthIn(max = 210.dp)
                    .shadow(elevation = 8.dp, shape = RoundedCornerShape(16.dp))
                    .clip(RoundedCornerShape(16.dp))
                    .background(BubbleBackground)
                    .border(width = 1.dp, color = BubbleBorder, shape = RoundedCornerShape(16.dp))
                    .padding(horizontal = 12.dp, vertical = 8.dp)
            ) {
                Text(
                    text = dialogue.orEmpty(),
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    lineHeight = 16.sp,
                    textAlign = TextAlign.Center
                )
            }

            // Downward pointing triangular tail
            Canvas(
                modifier = Modifier
                    .size(width = 14.dp, height = 7.dp)
                    .offset(y = (-1).dp)
            ) {
                val path = Path().apply {
                    moveTo(0f, 0f)
                    lineTo(size.width, 0f)
                    lineTo(size.width / 2, size.height)
                    close()
                }
                drawPath(path = path, color = BubbleBackground)
                // Bottom borders for the tail
                val borderPath = Path().apply {
                    moveTo(0f, 0f)
                    lineTo(size.width / 2, size.height)
                    lineTo(size.width, 0f)
                }
                drawPath(path = borderPath, color = BubbleBorder, style = Stroke(width = 1f))
            }
        }
    }
}
