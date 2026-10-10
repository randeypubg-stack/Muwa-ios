package app.muwa.nasheeds.ui.design

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.isActive

/** Three soft lights. Animation state is read during drawing, outside screen composition. */
@Composable
fun MuwaAmbientBackground(modifier: Modifier = Modifier) {
    val motionAllowed = rememberAmbientMotionAllowed()
    val drift = remember { Animatable(0f) }
    LaunchedEffect(motionAllowed) {
        if (!motionAllowed) {
            drift.snapTo(0f)
            return@LaunchedEffect
        }
        while (isActive) {
            drift.animateTo(1f, tween(MuwaMotion.AmbientDuration, easing = FastOutSlowInEasing))
            drift.animateTo(0f, tween(MuwaMotion.AmbientDuration, easing = FastOutSlowInEasing))
        }
    }
    Canvas(modifier.clearAndSetSemantics {}) {
        val phase = drift.value
        val span = maxOf(size.width, size.height).coerceAtMost(1200.dp.toPx())
        fun light(color: Color, radius: Float, x: Float, y: Float, strength: Float) {
            val center = Offset(size.width * x, size.height * y)
            drawCircle(
                Brush.radialGradient(
                    0f to color.copy(alpha = .32f * strength),
                    .36f to color.copy(alpha = .17f * strength),
                    .70f to color.copy(alpha = .045f * strength),
                    1f to Color.Transparent,
                    center = center,
                    radius = radius,
                ),
                radius = radius,
                center = center,
            )
        }
        drawRect(MuwaColors.Background)
        light(MuwaColors.Blue, span * .47f, .92f - .20f * phase, .12f + .13f * phase, 1f)
        light(MuwaColors.Teal, span * .36f, -.12f + .34f * phase, .60f - .15f * phase, .68f)
        light(MuwaColors.Violet, span * .40f, .70f + .22f * phase, .82f + .14f * phase, .72f)
        drawRect(
            Brush.verticalGradient(
                listOf(
                    Color.Transparent,
                    Color.Black.copy(alpha = .12f),
                    Color.Black.copy(alpha = .46f),
                )
            )
        )
    }
}
