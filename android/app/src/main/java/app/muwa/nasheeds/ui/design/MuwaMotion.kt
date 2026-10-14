package app.muwa.nasheeds.ui.design

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween

object MuwaMotion {
    const val AmbientDuration = 24_000

    fun press() = spring<Float>(dampingRatio = 0.78f, stiffness = 620f)

    fun <T> subtitleFocus() =
        tween<T>(durationMillis = 420, easing = CubicBezierEasing(0.22f, 1f, 0.36f, 1f))
}
