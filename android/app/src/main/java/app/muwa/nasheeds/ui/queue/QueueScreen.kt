package app.muwa.nasheeds.ui.queue

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.Track
import app.muwa.nasheeds.formatTime
import app.muwa.nasheeds.ui.components.Cover
import app.muwa.nasheeds.ui.components.MuwaIconButton
import app.muwa.nasheeds.ui.components.trackCount
import app.muwa.nasheeds.ui.design.MuwaColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun QueueScreen(model: MuwaModel, play: (Track) -> Unit) {
    val tracks = model.library.tracks(model.library.queue)
    val listState = rememberLazyListState()
    val haptics = LocalHapticFeedback.current
    var draggedId by remember { mutableStateOf<String?>(null) }
    var dragCenter by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(draggedId) {
        while (draggedId != null && isActive) {
            val layout = listState.layoutInfo
            val edge = 80f
            val scroll =
                when {
                    dragCenter < layout.viewportStartOffset + edge -> -14f
                    dragCenter > layout.viewportEndOffset - edge -> 14f
                    else -> 0f
                }
            if (scroll != 0f) {
                listState.scrollBy(scroll)
                val id = draggedId
                val target =
                    listState.layoutInfo.visibleItemsInfo.firstOrNull {
                        it.key != id && dragCenter >= it.offset && dragCenter <= it.offset + it.size
                    }
                val from = model.library.queue.indexOf(id)
                if (target != null && from >= 0) model.moveQueue(id!!, target.index - from)
            }
            delay(32)
        }
    }
    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp).testTag("queue.screen")) {
        Text(
            "${trackCount(tracks.size)} · ${tracks.sumOf { it.duration } / 60} мин",
            Modifier.padding(start = 6.dp, top = 4.dp, bottom = 18.dp),
            color = MuwaColors.Secondary,
            style = MaterialTheme.typography.bodySmall,
        )
        if (tracks.isEmpty()) {
            Column(
                Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.QueueMusic,
                    null,
                    Modifier.size(48.dp),
                    tint = MuwaColors.Ice,
                )
                Text(
                    "Очередь пуста",
                    Modifier.padding(top = 18.dp),
                    style = MaterialTheme.typography.titleLarge,
                )
                Text(
                    "Добавьте нашиды через меню ⋮.",
                    Modifier.padding(top = 8.dp),
                    color = MuwaColors.Secondary,
                )
            }
        } else
            LazyColumn(
                state = listState,
                verticalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(bottom = 24.dp),
            ) {
                items(tracks, key = { it.id }) { track ->
                    val current = model.track?.id == track.id
                    val shape = RoundedCornerShape(22.dp)
                    Row(
                        Modifier.fillMaxWidth()
                            .then(if (draggedId == track.id) Modifier else Modifier.animateItem())
                            .zIndex(if (draggedId == track.id) 1f else 0f)
                            .graphicsLayer {
                                if (draggedId == track.id) {
                                    val item =
                                        listState.layoutInfo.visibleItemsInfo.firstOrNull {
                                            it.key == track.id
                                        }
                                    translationY =
                                        item?.let { dragCenter - it.offset - it.size / 2f } ?: 0f
                                }
                            }
                            .background(
                                if (current) MuwaColors.Ice.copy(alpha = .075f)
                                else Color.White.copy(alpha = .025f),
                                shape,
                            )
                            .border(
                                .75.dp,
                                Color.White.copy(alpha = if (current) .12f else .055f),
                                shape,
                            )
                            .padding(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Row(
                            Modifier.weight(1f).clickable { play(track) }.padding(2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Cover(track, Modifier.size(48.dp))
                            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                                Text(
                                    track.title,
                                    style = MaterialTheme.typography.titleMedium,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(
                                        track.artist,
                                        Modifier.weight(1f),
                                        color = MuwaColors.Secondary,
                                        style = MaterialTheme.typography.labelSmall,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Text(
                                        formatTime(track.duration * 1000),
                                        color = MuwaColors.Secondary,
                                        style = MaterialTheme.typography.labelSmall,
                                        maxLines = 1,
                                    )
                                }
                                if (current)
                                    Text(
                                        if (model.playing) "Сейчас играет" else "На паузе",
                                        color = MuwaColors.Ice,
                                        style = MaterialTheme.typography.labelSmall,
                                    )
                            }
                        }
                        MuwaIconButton(
                            Icons.Default.Remove,
                            "Удалить ${track.title} из очереди",
                            {
                                model.removeQueue(track.id)
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            },
                            Modifier.testTag("queue.remove.${track.id}"),
                        )
                        var menu by remember { mutableStateOf(false) }
                        Box {
                            val reorder =
                                Modifier.pointerInput(track.id) {
                                        detectDragGesturesAfterLongPress(
                                            onDragStart = {
                                                listState.layoutInfo.visibleItemsInfo
                                                    .firstOrNull { it.key == track.id }
                                                    ?.let {
                                                        draggedId = track.id
                                                        dragCenter = it.offset + it.size / 2f
                                                        haptics.performHapticFeedback(
                                                            HapticFeedbackType.LongPress
                                                        )
                                                    }
                                            },
                                            onDragEnd = { draggedId = null },
                                            onDragCancel = { draggedId = null },
                                        ) { change, amount ->
                                            change.consume()
                                            dragCenter += amount.y
                                            val target =
                                                listState.layoutInfo.visibleItemsInfo.firstOrNull {
                                                    it.key != track.id &&
                                                        dragCenter >= it.offset &&
                                                        dragCenter <= it.offset + it.size
                                                }
                                            if (target != null) {
                                                val from = model.library.queue.indexOf(track.id)
                                                if (from >= 0)
                                                    model.moveQueue(track.id, target.index - from)
                                            }
                                        }
                                    }
                                    .semantics {
                                        customActions =
                                            listOf(
                                                CustomAccessibilityAction("Переместить выше") {
                                                    model.moveQueue(track.id, -1)
                                                    true
                                                },
                                                CustomAccessibilityAction("Переместить ниже") {
                                                    model.moveQueue(track.id, 1)
                                                    true
                                                },
                                            )
                                    }
                            MuwaIconButton(
                                Icons.Default.Menu,
                                "Порядок ${track.title}",
                                { menu = true },
                                reorder,
                            )
                            DropdownMenu(menu, { menu = false }) {
                                DropdownMenuItem(
                                    text = { Text("Переместить выше") },
                                    enabled = tracks.firstOrNull()?.id != track.id,
                                    onClick = {
                                        model.moveQueue(track.id, -1)
                                        menu = false
                                    },
                                    leadingIcon = { Icon(Icons.Default.KeyboardArrowUp, null) },
                                )
                                DropdownMenuItem(
                                    text = { Text("Переместить ниже") },
                                    enabled = tracks.lastOrNull()?.id != track.id,
                                    onClick = {
                                        model.moveQueue(track.id, 1)
                                        menu = false
                                    },
                                    leadingIcon = { Icon(Icons.Default.KeyboardArrowDown, null) },
                                )
                            }
                        }
                    }
                }
            }
    }
}
