package app.muwa.nasheeds

import android.animation.ValueAnimator
import android.os.Build
import android.view.View
import android.view.ViewTreeObserver
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.math.PI
import kotlin.math.sin

/** UI-only cold-launch reveal. Home and its model mount immediately beneath it. */
@Composable
fun MuwaLaunchHost(showIntro: Boolean, systemLaunchReady: Boolean = true, content: @Composable () -> Unit) {
    // This is deliberately not saveable: rotation/recreation must not replay the launch.
    var introVisible by remember { mutableStateOf(showIntro && ValueAnimator.areAnimatorsEnabled()) }
    LaunchedEffect(introVisible) {
        if (introVisible) {
            // System splash/focus/frame-commit callbacks can be lost when a
            // renderer is recreated. A decorative reveal must never hide the
            // already-mounted home indefinitely; fall back to usable content.
            delay(3000)
            introVisible = false
        }
    }
    Box(Modifier.fillMaxSize()) {
        Box(if (introVisible) Modifier.clearAndSetSemantics { } else Modifier) { content() }
        if (introVisible) MuwaLaunchIntro(systemLaunchReady) { introVisible = false }
    }
}

@Composable
private fun MuwaLaunchIntro(systemLaunchReady: Boolean, onFinished: () -> Unit) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val view = LocalView.current
    val finish by rememberUpdatedState(onFinished)
    val progress = remember { Animatable(0f) }
    // Screen readers receive the app name once; taps/back never activate hidden home.
    BackHandler { }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) finish()
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(lifecycle, view, systemLaunchReady) {
        if (!systemLaunchReady) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            try {
                // A resumed Activity may still be covered by Android's starting
                // window. Begin the visual clock only after a focused frame has
                // reached the GPU, rather than consuming it during cold setup.
                awaitWindowFocus(view)
                awaitFrameCommit(view)
                progress.animateTo(1f, tween(durationMillis = ((1f - progress.value) * 1050).toInt(), easing = LinearEasing))
            } finally {
                // Pausing/cancellation reveals usable home and never resumes a
                // partly hidden launch when the user comes back.
                finish()
            }
        }
    }
    val phase = progress.value
    // A faint first frame primes the real logo texture before animation starts.
    val appear = 0.04f + 0.96f * smoothStep((phase / 0.24f).coerceIn(0f, 1f))
    val settle = smoothStep((phase / 0.64f).coerceIn(0f, 1f))
    val fade = 1f - smoothStep(((phase - 0.81f) / 0.19f).coerceIn(0f, 1f))
    val sheen = ((phase - 0.18f) / 0.60f).coerceIn(0f, 1f)
    val sheenOpacity = sin(sheen * PI).toFloat() * 0.17f
    val markPainter = painterResource(R.drawable.app_mark)
    // A luminance-derived alpha mask keeps the glint on the silver mark. The black
    // canvas of a supplied PNG stays black; there is no rectangular light stripe.
    val sheenFilter = remember {
        ColorFilter.colorMatrix(ColorMatrix(floatArrayOf(
            0f, 0f, 0f, 0f, 205f,
            0f, 0f, 0f, 0f, 237f,
            0f, 0f, 0f, 0f, 255f,
            0.2126f, 0.7152f, 0.0722f, 0f, 0f
        )))
    }
    BoxWithConstraints(
        Modifier.fillMaxSize().testTag("launch.intro")
            .graphicsLayer { alpha = fade }
            .background(Color.Black)
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) awaitPointerEvent().changes.forEach { it.consume() }
                }
            },
        contentAlignment = Alignment.Center
    ) {
        val imageSize = minOf(minOf(maxWidth, maxHeight) * 0.90f, 440.dp)
        Box(Modifier.size(imageSize).graphicsLayer {
            alpha = appear
            scaleX = 0.91f + 0.09f * settle
            scaleY = scaleX
            translationY = (1f - settle) * 12.dp.toPx()
        }) {
            Image(markPainter, contentDescription = "Muwa", modifier = Modifier.fillMaxSize())
            Image(markPainter, contentDescription = null, colorFilter = sheenFilter,
                modifier = Modifier.fillMaxSize()
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen; alpha = 0.005f + sheenOpacity }
                    .drawWithContent {
                        drawContent()
                        val center = (-0.40f + 1.80f * sheen) * size.width
                        drawRect(
                            brush = Brush.linearGradient(
                                0f to Color.Transparent,
                                0.5f to Color.White,
                                1f to Color.Transparent,
                                start = Offset(center - size.width * 0.14f, 0f),
                                end = Offset(center + size.width * 0.14f, size.height * 0.24f)
                            ),
                            blendMode = BlendMode.DstIn
                        )
                    }
            )
        }
    }
}

private fun smoothStep(value: Float): Float = value * value * (3f - 2f * value)

private suspend fun awaitWindowFocus(view: View) {
    if (view.hasWindowFocus()) return
    suspendCancellableCoroutine<Unit> { continuation ->
        val listener = object : ViewTreeObserver.OnWindowFocusChangeListener {
            override fun onWindowFocusChanged(hasFocus: Boolean) {
                if (hasFocus && continuation.isActive) {
                    view.viewTreeObserver.takeIf { it.isAlive }?.removeOnWindowFocusChangeListener(this)
                    continuation.resume(Unit)
                }
            }
        }
        view.viewTreeObserver.addOnWindowFocusChangeListener(listener)
        continuation.invokeOnCancellation {
            view.viewTreeObserver.takeIf { it.isAlive }?.removeOnWindowFocusChangeListener(listener)
        }
        // Focus can arrive between the initial check and listener registration.
        listener.onWindowFocusChanged(view.hasWindowFocus())
    }
}

private suspend fun awaitFrameCommit(view: View) {
    if (Build.VERSION.SDK_INT >= 29 && view.isHardwareAccelerated) {
        suspendCancellableCoroutine<Unit> { continuation ->
            val committed = Runnable { if (continuation.isActive) continuation.resume(Unit) }
            view.viewTreeObserver.registerFrameCommitCallback(committed)
            continuation.invokeOnCancellation {
                view.viewTreeObserver.takeIf { it.isAlive }?.unregisterFrameCommitCallback(committed)
            }
            view.postInvalidateOnAnimation()
        }
    } else {
        // Older/software renderers expose the frame clock, but no commit API.
        withFrameNanos { }
        withFrameNanos { }
    }
}
