package app.muwa.nasheeds.ui.player

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.ui.components.Cover
import kotlin.math.abs
import kotlinx.coroutines.launch

@Composable
internal fun SwipeCover(model: MuwaModel, size: androidx.compose.ui.unit.Dp, onClose: () -> Unit) {
    val track = model.track ?: return
    val offset = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    var horizontal by remember { mutableStateOf<Boolean?>(null) }
    var travel by remember { mutableFloatStateOf(1f) }
    var locked by remember { mutableStateOf(false) }
    val queue = model.library.tracks(model.library.queue)
    val index = queue.indexOfFirst { it.id == track.id }
    val neighbor = queue.getOrNull(index + if (offset.value <= 0) 1 else -1)
    val currentNeighbor by rememberUpdatedState(neighbor)
    Box(
        Modifier.size(size).pointerInput(track.id) {
            detectDragGestures(
                onDragStart = {
                    horizontal = null
                    travel = this.size.width.toFloat()
                },
                onDragCancel = { if (!locked) scope.launch { offset.animateTo(0f) } },
                onDragEnd = {
                    if (locked) return@detectDragGestures
                    val destination = currentNeighbor
                    if (
                        horizontal == true &&
                            abs(offset.value) > travel * .25f &&
                            destination != null
                    ) {
                        locked = true
                        scope.launch {
                            try {
                                offset.animateTo(
                                    if (offset.value < 0) -travel else travel,
                                    spring(),
                                )
                                if (model.track?.id == track.id) model.play(destination)
                            } finally {
                                offset.snapTo(0f)
                                locked = false
                            }
                        }
                    } else {
                        if (horizontal == false && offset.value > 80) onClose()
                        scope.launch { offset.animateTo(0f) }
                    }
                },
            ) { change, amount ->
                if (locked) return@detectDragGestures
                if (horizontal == null && (abs(amount.x) > 1 || abs(amount.y) > 1))
                    horizontal = abs(amount.x) > abs(amount.y)
                val delta = if (horizontal == true) amount.x else amount.y
                scope.launch { offset.snapTo((offset.value + delta).coerceIn(-travel, travel)) }
                change.consume()
            }
        }
    ) {
        val progress = (abs(offset.value) / travel).coerceIn(0f, 1f)
        Cover(
            track,
            Modifier.fillMaxSize().graphicsLayer {
                translationX = if (horizontal == true) offset.value else 0f
                translationY = if (horizontal == false) offset.value.coerceAtLeast(0f) else 0f
                scaleX = 1f - .28f * progress
                scaleY = scaleX
            },
            radius = 28.dp,
            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
        )
        if (horizontal == true && neighbor != null)
            Cover(
                neighbor,
                Modifier.fillMaxSize().graphicsLayer {
                    translationX = offset.value + if (offset.value < 0) travel else -travel
                    scaleX = .72f + .28f * progress
                    scaleY = scaleX
                    alpha = progress
                },
                radius = 28.dp,
                contentScale = androidx.compose.ui.layout.ContentScale.Crop,
            )
    }
}

@Composable
internal fun PlayerArtworkAndLyrics(
    model: MuwaModel,
    size: androidx.compose.ui.unit.Dp,
    visible: Boolean,
    onClose: () -> Unit,
    onReader: () -> Unit,
) {
    val motion = app.muwa.nasheeds.ui.design.rememberAmbientMotionAllowed()
    val coverSize by
        androidx.compose.animation.core.animateDpAsState(
            if (visible) size * .74f else size,
            if (motion)
                androidx.compose.animation.core.spring(dampingRatio = .94f, stiffness = 500f)
            else androidx.compose.animation.core.snap(),
            label = "artwork.lyrics",
        )
    Row(
        Modifier.fillMaxWidth().height(size),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        SwipeCover(model, coverSize, onClose)
        if (visible) {
            val active =
                model.subtitles
                    .indexOfFirst {
                        model.position / 1000.0 >= it.optDouble("start") &&
                            model.position / 1000.0 < it.optDouble("end")
                    }
                    .coerceAtLeast(0)
            Column(
                Modifier.padding(start = 12.dp)
                    .widthIn(max = 124.dp)
                    .weight(1f, fill = false)
                    .fillMaxHeight()
                    .verticalScroll(rememberScrollState())
                    .testTag("player.lyrics")
                    .clickable(onClick = onReader),
                verticalArrangement = Arrangement.Center,
            ) {
                listOf(active - 1, active, active + 1).forEach { index ->
                    val phrase = model.subtitles.getOrNull(index)?.optString("ar").orEmpty()
                    androidx.compose.material3.Text(
                        phrase,
                        Modifier.fillMaxWidth().padding(vertical = 7.dp),
                        fontSize = if (index == active) 18.sp else 12.sp,
                        fontWeight =
                            if (index == active) androidx.compose.ui.text.font.FontWeight.SemiBold
                            else androidx.compose.ui.text.font.FontWeight.Normal,
                        color =
                            androidx.compose.ui.graphics.Color.White.copy(
                                alpha = if (index == active) 1f else .32f
                            ),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Right,
                        style =
                            androidx.compose.ui.text.TextStyle(
                                textDirection =
                                    androidx.compose.ui.text.style.TextDirection.ContentOrRtl
                            ),
                    )
                }
                androidx.compose.material3.Icon(
                    androidx.compose.material.icons.Icons.Default.OpenInFull,
                    "Открыть текст нашида",
                    Modifier.align(androidx.compose.ui.Alignment.End)
                        .padding(top = 8.dp)
                        .size(16.dp),
                    tint = androidx.compose.ui.graphics.Color.White.copy(alpha = .6f),
                )
            }
        }
    }
}
