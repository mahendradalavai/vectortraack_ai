package com.example.kitten.ui.character

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val HeadGradientTop = Color(0xFFFB923C) // orange-400
private val HeadGradientBottom = Color(0xFFF59E0B) // amber-500
private val HeadBorder = Color(0xFFF97316)
private val CreamCheeks = Color(0xFFFFFBEB) // amber-50
private val CreamCheekBorder = Color(0xFFFEF3C7) // amber-100
private val TinyNose = Color(0xFFFB7185) // rose-400
private val MouthMouthBrown = Color(0xFF78350F) // amber-900

private val PulseEmerald = Color(0xFF34D399) // emerald-400
private val PulseTeal = Color(0xFF5EEAD4) // teal-300
private val PulseOrange = Color(0xFFFB923C) // orange-400

/**
 * Native vector kitten body: orange/amber head gradient, cream cheek patch,
 * tiny pink nose, and "ω" / "zZ" mouth. Also manages listening acoustic
 * pulse rings and drag pulse effects.
 */
@Composable
fun KittenBody(
    state: KittenState,
    isDragging: Boolean,
    modifier: Modifier = Modifier
) {
    val isListening = state == KittenState.LISTENING

    val infiniteTransition = rememberInfiniteTransition(label = "pulseEffects")

    // Listening acoustic wave expansion 1
    val pulseProgress1 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "listeningPulse1"
    )

    // Listening acoustic wave expansion 2 (staggered)
    val pulseProgress2 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1400, delayMillis = 400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "listeningPulse2"
    )

    // Drag pulse expansion
    val dragPulseProgress by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 900, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "dragPulse"
    )

    // Listening badge bounce
    val badgeBounce by infiniteTransition.animateFloat(
        initialValue = -3f,
        targetValue = 3f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 400, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "badgeBounce"
    )

    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        // --- Vector Pulse Rings behind the kitten ---
        Canvas(modifier = Modifier.fillMaxSize()) {
            val center = Offset(size.width / 2, size.height / 2)
            val baseRadius = size.width * 0.44f

            if (isListening) {
                // Expanding emerald acoustic ring
                val r1 = baseRadius + (pulseProgress1 * size.width * 0.18f)
                val alpha1 = (1f - pulseProgress1).coerceIn(0f, 0.75f)
                drawCircle(
                    color = PulseEmerald.copy(alpha = alpha1),
                    radius = r1,
                    center = center,
                    style = Stroke(width = 2.5f)
                )

                // Expanding teal acoustic ring
                val r2 = baseRadius + (pulseProgress2 * size.width * 0.14f)
                val alpha2 = (1f - pulseProgress2).coerceIn(0f, 0.60f)
                drawCircle(
                    color = PulseTeal.copy(alpha = alpha2),
                    radius = r2,
                    center = center,
                    style = Stroke(width = 1.8f)
                )
            }

            if (isDragging) {
                // Orange ping ring while dragging
                val rDrag = baseRadius + (dragPulseProgress * size.width * 0.16f)
                val alphaDrag = (1f - dragPulseProgress).coerceIn(0f, 0.65f)
                drawCircle(
                    color = PulseOrange.copy(alpha = alphaDrag),
                    radius = rDrag,
                    center = center,
                    style = Stroke(width = 2.5f)
                )
            }
        }

        // --- Kitten Head, Cheeks, Nose, Mouth ---
        Canvas(modifier = Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height

            // Head bounds
            val headLeft = w * 0.08f
            val headTop = h * 0.10f
            val headRight = w * 0.92f
            val headBottom = h * 0.90f
            val headWidth = headRight - headLeft
            val headHeight = headBottom - headTop

            val headPath = Path().apply {
                addRoundRect(
                    RoundRect(
                        left = headLeft,
                        top = headTop,
                        right = headRight,
                        bottom = headBottom,
                        cornerRadius = CornerRadius(headWidth / 2, headHeight / 2)
                    )
                )
            }

            // Head Orange/Amber gradient
            val gradientBrush = Brush.verticalGradient(
                colors = listOf(HeadGradientTop, HeadGradientBottom),
                startY = headTop,
                endY = headBottom
            )
            drawPath(path = headPath, brush = gradientBrush)
            drawPath(path = headPath, color = HeadBorder, style = Stroke(width = 2.5f))

            // Cream Cheeks patch (lower half of face)
            val cheekTop = headTop + (headHeight * 0.42f)
            val cheekHeight = headBottom - cheekTop

            // Clip cheeks to head bounds
            val cheekPath = Path().apply {
                // Symmetrical cheek arc
                moveTo(headLeft, cheekTop + (cheekHeight * 0.4f))
                cubicTo(
                    headLeft + headWidth * 0.2f, cheekTop,
                    headLeft + headWidth * 0.4f, cheekTop - (cheekHeight * 0.1f),
                    w / 2, cheekTop - (cheekHeight * 0.05f)
                )
                cubicTo(
                    headRight - headWidth * 0.4f, cheekTop - (cheekHeight * 0.1f),
                    headRight - headWidth * 0.2f, cheekTop,
                    headRight, cheekTop + (cheekHeight * 0.4f)
                )
                lineTo(headRight, headBottom)
                lineTo(headLeft, headBottom)
                close()
            }

            // Draw cheeks clipped inside head
            drawPath(path = cheekPath, color = CreamCheeks)
            drawPath(
                path = cheekPath,
                color = CreamCheekBorder,
                style = Stroke(width = 1.2f)
            )

            // --- Tiny Pink Nose ---
            val noseCenterX = w / 2
            val noseCenterY = headTop + (headHeight * 0.58f)
            val noseWidth = headWidth * 0.09f
            val noseHeight = headHeight * 0.06f
            drawRoundRect(
                color = TinyNose,
                topLeft = Offset(noseCenterX - (noseWidth / 2), noseCenterY - (noseHeight / 2)),
                size = Size(noseWidth, noseHeight),
                cornerRadius = CornerRadius(noseWidth / 2, noseHeight / 2)
            )

            // --- Cute "ω" Mouth or Sleep State ---
            val mouthY = noseCenterY + (noseHeight * 0.7f)
            if (state == KittenState.SLEEPING) {
                // Sleep: gentle horizontal closed arc
                val sleepW = headWidth * 0.10f
                val sleepPath = Path().apply {
                    moveTo(noseCenterX - sleepW / 2, mouthY)
                    quadraticTo(noseCenterX, mouthY + (headHeight * 0.02f), noseCenterX + sleepW / 2, mouthY)
                }
                drawPath(
                    path = sleepPath,
                    color = MouthMouthBrown,
                    style = Stroke(width = 1.8f, cap = StrokeCap.Round)
                )
            } else if (state == KittenState.HAPPY) {
                // Happy open curved smile
                val happyW = headWidth * 0.14f
                val happyPath = Path().apply {
                    moveTo(noseCenterX - happyW / 2, mouthY)
                    quadraticTo(noseCenterX, mouthY + (headHeight * 0.06f), noseCenterX + happyW / 2, mouthY)
                }
                drawPath(
                    path = happyPath,
                    color = MouthMouthBrown,
                    style = Stroke(width = 2f, cap = StrokeCap.Round)
                )
            } else {
                // Classic "ω" double arc mouth
                val loopW = headWidth * 0.06f
                val loopH = headHeight * 0.035f

                // Left loop of ω
                val leftLoop = Path().apply {
                    moveTo(noseCenterX, mouthY)
                    cubicTo(
                        noseCenterX - (loopW * 0.3f), mouthY + loopH,
                        noseCenterX - loopW, mouthY + loopH,
                        noseCenterX - loopW, mouthY + (loopH * 0.4f)
                    )
                }
                drawPath(
                    path = leftLoop,
                    color = MouthMouthBrown,
                    style = Stroke(width = 1.8f, cap = StrokeCap.Round)
                )

                // Right loop of ω
                val rightLoop = Path().apply {
                    moveTo(noseCenterX, mouthY)
                    cubicTo(
                        noseCenterX + (loopW * 0.3f), mouthY + loopH,
                        noseCenterX + loopW, mouthY + loopH,
                        noseCenterX + loopW, mouthY + (loopH * 0.4f)
                    )
                }
                drawPath(
                    path = rightLoop,
                    color = MouthMouthBrown,
                    style = Stroke(width = 1.8f, cap = StrokeCap.Round)
                )
            }
        }

        // --- Sleeping "zZ" indicator text near face ---
        if (state == KittenState.SLEEPING) {
            Text(
                text = "zZ",
                color = MouthMouthBrown,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .align(Alignment.Center)
                    .offset(x = 18.dp, y = (-2).dp)
            )
        }

        // --- Listening Badge ---
        if (isListening) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = 12.dp, y = ((-4) + badgeBounce).dp)
                    .shadow(elevation = 4.dp, shape = RoundedCornerShape(12.dp))
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color(0xFF10B981))
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "🎙️",
                        fontSize = 9.sp
                    )
                    Text(
                        text = "Listening",
                        color = Color.White,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(start = 2.dp)
                    )
                }
            }
        }
    }
}
