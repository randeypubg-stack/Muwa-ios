package app.muwa.nasheeds

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import app.muwa.nasheeds.ui.components.Cover
import app.muwa.nasheeds.ui.design.rememberAmbientMotionAllowed
import kotlin.math.abs
import kotlinx.coroutines.launch

@Composable
fun PlayerSheet(
    model: MuwaModel,
    onClose: () -> Unit,
    onQueue: () -> Unit,
    onSubtitles: () -> Unit,
    onPlaylist: () -> Unit,
) {
    val track = model.track ?: return
    var slider by remember { mutableStateOf<Float?>(null) }
    var menu by remember { mutableStateOf(false) }
    // Share the Activity's viewport and consume its insets exactly once. A
    // separate Dialog window is shifted by Android 17's edge-to-edge handling.
    // The background covers system bars; all controls stay in safeDrawing.
    CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
        BoxWithConstraints(
            Modifier.fillMaxSize()
                .testTag("player.screen")
                .background(Color(0xFF080D16))
                .clipToBounds()
                .pointerInput(Unit) { detectTapGestures {} }
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            val wide = maxWidth > maxHeight || maxWidth > 700.dp
            val compactControls = wide && maxHeight < 400.dp
            Column(Modifier.fillMaxSize().testTag("player.safe-content")) {
                Row(
                    Modifier.fillMaxWidth().pointerInput(Unit) {
                        detectDragGestures { change, amount ->
                            if (amount.y > 10) onClose()
                            change.consume()
                        }
                    },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onClose, modifier = Modifier.testTag("player.close")) {
                        Icon(Icons.Default.KeyboardArrowDown, "Закрыть плеер")
                    }
                    Text("Сейчас играет", Modifier.weight(1f), color = Color.Gray)
                    Box {
                        IconButton(onClick = { menu = true }) {
                            Icon(Icons.Default.MoreVert, "Меню плеера")
                        }
                        DropdownMenu(menu, { menu = false }) {
                            DropdownMenuItem(
                                text = { Text("Добавить в плейлист") },
                                onClick = {
                                    menu = false
                                    onPlaylist()
                                },
                            )
                            listOf(15, 30, 45, 60).forEach { minutes ->
                                DropdownMenuItem(
                                    text = { Text("Таймер сна · $minutes минут") },
                                    onClick = {
                                        SleepTimer.start(minutes)
                                        menu = false
                                    },
                                )
                            }
                            DropdownMenuItem(
                                text = { Text("После текущего нашида") },
                                onClick = {
                                    SleepTimer.afterCurrent()
                                    menu = false
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Отменить таймер") },
                                onClick = {
                                    SleepTimer.cancel()
                                    menu = false
                                },
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        if (track.id in model.downloads.downloaded)
                                            "Удалить загрузку"
                                        else "Скачать MP3"
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        if (track.id in model.downloads.downloaded)
                                            Icons.Default.Delete
                                        else Icons.Default.Download,
                                        null,
                                    )
                                },
                                onClick = {
                                    menu = false
                                    if (track.id in model.downloads.downloaded)
                                        runCatching { model.downloads.remove(track) }
                                            .onFailure { model.error = it.message }
                                    else
                                        model.downloads.download(track) { model.error = it.message }
                                },
                            )
                            if (model.downloads.progress.containsKey(track.id))
                                DropdownMenuItem(
                                    text = { Text("Отменить скачивание") },
                                    onClick = {
                                        model.downloads.cancel(track)
                                        menu = false
                                    },
                                )
                        }
                    }
                }
                val controls: @Composable (Modifier) -> Unit = { modifier ->
                    Column(
                        modifier.fillMaxWidth().padding(horizontal = 16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement =
                            Arrangement.spacedBy(
                                if (wide) 4.dp else 8.dp,
                                Alignment.CenterVertically,
                            ),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(
                                    track.title,
                                    style =
                                        if (wide) MaterialTheme.typography.titleLarge
                                        else MaterialTheme.typography.headlineSmall,
                                    maxLines = if (wide) 1 else 2,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(
                                    track.artist,
                                    color = Color.Gray,
                                    style =
                                        if (compactControls) MaterialTheme.typography.bodySmall
                                        else MaterialTheme.typography.bodyLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            IconButton(onClick = { model.library.like(track) }) {
                                Icon(
                                    if (track.id in model.library.favorites) Icons.Default.Favorite
                                    else Icons.Default.FavoriteBorder,
                                    "Избранное",
                                )
                            }
                        }
                        Row(
                            Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            if (compactControls)
                                Text(
                                    formatTime(model.position),
                                    style = MaterialTheme.typography.labelMedium,
                                )
                            Slider(
                                value =
                                    slider
                                        ?: (if (model.duration > 0)
                                                model.position.toFloat() / model.duration
                                            else 0f)
                                            .coerceIn(0f, 1f),
                                onValueChange = { slider = it },
                                onValueChangeFinished = {
                                    slider?.let { model.seek((it * model.duration).toLong()) }
                                    slider = null
                                },
                                modifier = Modifier.weight(1f).testTag("player.seek"),
                            )
                            if (compactControls)
                                Text(
                                    formatTime(model.duration),
                                    style = MaterialTheme.typography.labelMedium,
                                )
                        }
                        if (!compactControls)
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(formatTime(model.position))
                                Text(formatTime(model.duration))
                            }
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            IconButton(onClick = model::toggleShuffle) {
                                Icon(
                                    Icons.Default.Shuffle,
                                    "Перемешать",
                                    tint =
                                        if (model.shuffle) MaterialTheme.colorScheme.primary
                                        else Color.Gray,
                                )
                            }
                            IconButton(onClick = model::previous) {
                                Icon(Icons.Default.SkipPrevious, "Предыдущий")
                            }
                            Box(contentAlignment = Alignment.Center) {
                                val playSize = if (wide) 56.dp else 62.dp
                                FilledIconButton(
                                    onClick = model::toggle,
                                    modifier = Modifier.size(playSize).testTag("player.toggle"),
                                ) {
                                    Icon(
                                        if (model.playing) Icons.Default.Pause
                                        else Icons.Default.PlayArrow,
                                        "Воспроизведение",
                                    )
                                }
                                if (model.buffering) {
                                    val motion = rememberAmbientMotionAllowed()
                                    val ring =
                                        Modifier.size(playSize + 10.dp).clearAndSetSemantics {}
                                    if (motion)
                                        CircularProgressIndicator(
                                            modifier = ring,
                                            strokeWidth = 1.5.dp,
                                            color = Color.White,
                                        )
                                    else
                                        CircularProgressIndicator(
                                            progress = { .72f },
                                            modifier = ring,
                                            strokeWidth = 1.5.dp,
                                            color = Color.White,
                                        )
                                }
                            }
                            IconButton(onClick = model::next) {
                                Icon(Icons.Default.SkipNext, "Следующий")
                            }
                            IconButton(onClick = model::cycleRepeat) {
                                Icon(
                                    if (model.repeat == Player.REPEAT_MODE_ONE)
                                        Icons.Default.RepeatOne
                                    else Icons.Default.Repeat,
                                    "Повтор",
                                    tint =
                                        if (model.repeat == Player.REPEAT_MODE_OFF) Color.Gray
                                        else MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                        model.downloads.progress[track.id]?.let {
                            LinearProgressIndicator(
                                progress = { it },
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                        if (SleepTimer.endAt != null || SleepTimer.afterTrack)
                            Text(
                                if (SleepTimer.afterTrack) "Таймер: после текущего нашида"
                                else "Таймер сна включён",
                                color = Color.Gray,
                            )
                        if (model.error != null)
                            TextButton(onClick = model::retry) { Text("Повторить воспроизведение") }
                    }
                }
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                    // Reserve a measured body below the header and above
                    // the fixed actions. Short screens can scroll this body,
                    // including status/errors, without moving its actions
                    // beneath the navigation bar.
                    val artworkSize =
                        if (wide) minOf((maxHeight - 16.dp).coerceAtLeast(72.dp), maxWidth * .4f)
                        else minOf(maxWidth - 48.dp, maxHeight * .43f).coerceAtLeast(72.dp)
                    if (wide)
                        Row(
                            Modifier.fillMaxSize(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                                SwipeCover(model, artworkSize, onClose)
                            }
                            controls(
                                Modifier.weight(1f)
                                    .fillMaxHeight()
                                    .verticalScroll(rememberScrollState())
                            )
                        }
                    else
                        Column(
                            Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement =
                                Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
                        ) {
                            SwipeCover(model, artworkSize, onClose)
                            controls(Modifier)
                        }
                }
                Row(
                    Modifier.fillMaxWidth().padding(top = 8.dp),
                    horizontalArrangement = Arrangement.Center,
                ) {
                    TextButton(
                        onClick = onSubtitles,
                        modifier = Modifier.testTag("player.subtitles"),
                    ) {
                        Text("Текст")
                    }
                    TextButton(onClick = onQueue, modifier = Modifier.testTag("player.queue")) {
                        Text("Очередь")
                    }
                }
            }
        }
    }
}

@Composable
private fun SwipeCover(model: MuwaModel, size: androidx.compose.ui.unit.Dp, onClose: () -> Unit) {
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
            )
    }
}
