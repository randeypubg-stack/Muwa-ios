package app.muwa.nasheeds.ui.player

import android.content.Intent
import android.media.MediaRouter2
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.Player
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.design.*

@Composable
internal fun PlayerAction(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 44.dp,
    enabled: Boolean = true,
    active: Boolean = false,
) {
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier =
            modifier
                .size(size)
                .background(
                    Color.White.copy(alpha = if (active) .14f else .055f),
                    RoundedCornerShape(16.dp),
                ),
    ) {
        Icon(
            icon,
            label,
            Modifier.size(22.dp),
            tint = Color.White.copy(alpha = if (enabled) 1f else .38f),
        )
    }
}

@Composable
internal fun PlayerMetadata(model: MuwaModel, compact: Boolean) {
    val track = model.track ?: return
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(
                track.title,
                fontSize = if (compact) 18.sp else 28.sp,
                lineHeight = if (compact) 22.sp else 34.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                track.artist,
                fontSize = 13.sp,
                lineHeight = 16.sp,
                color = MuwaColors.Secondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(
            onClick = { model.library.like(track) },
            modifier = Modifier.size(42.dp).background(Color.White.copy(alpha = .055f), CircleShape),
        ) {
            Icon(
                if (track.id in model.library.favorites) Icons.Default.Favorite
                else Icons.Default.FavoriteBorder,
                "Избранное",
                tint = if (track.id in model.library.favorites) Color(0xFFFF6B97) else Color.White,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PlayerScrubber(model: MuwaModel, compact: Boolean = false) {
    var draft by remember(model.track?.id) { mutableStateOf<Float?>(null) }
    val slider: @Composable (Modifier) -> Unit = { modifier ->
        Slider(
            value =
                draft
                    ?: (if (model.duration > 0) model.position.toFloat() / model.duration else 0f)
                        .coerceIn(0f, 1f),
            onValueChange = { draft = it },
            onValueChangeFinished = {
                draft?.let { model.seek((it * model.duration).toLong()) }
                draft = null
            },
            modifier = modifier.height(32.dp).testTag("player.seek"),
            colors =
                SliderDefaults.colors(
                    thumbColor = Color.White,
                    activeTrackColor = Color.White,
                    inactiveTrackColor = Color.White.copy(alpha = .13f),
                ),
            thumb = { Box(Modifier.size(36.dp, 24.dp).background(Color.White, CircleShape)) },
            track = { state ->
                SliderDefaults.Track(
                    state,
                    Modifier.height(5.dp),
                    colors =
                        SliderDefaults.colors(
                            activeTrackColor = Color.White,
                            inactiveTrackColor = Color.White.copy(alpha = .13f),
                        ),
                    thumbTrackGapSize = 0.dp,
                    drawStopIndicator = null,
                )
            },
        )
    }
    if (compact)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                formatTime(model.position),
                fontSize = 10.sp,
                lineHeight = 14.sp,
                color = MuwaColors.Secondary,
            )
            slider(Modifier.weight(1f).padding(horizontal = 6.dp))
            Text(
                formatTime(model.duration),
                fontSize = 10.sp,
                lineHeight = 14.sp,
                color = MuwaColors.Secondary,
            )
        }
    else
        Column {
            slider(Modifier.fillMaxWidth())
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    formatTime(draft?.let { (it * model.duration).toLong() } ?: model.position),
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    color = MuwaColors.Secondary,
                )
                Text(
                    formatTime(model.duration),
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    color = MuwaColors.Secondary,
                )
            }
        }
}

@Composable
internal fun PlayerTransport(model: MuwaModel, compact: Boolean, shortWindow: Boolean = false) {
    val playSize = if (shortWindow) 48.dp else if (compact) 58.dp else 68.dp
    val motion = rememberAmbientMotionAllowed()
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement =
            Arrangement.spacedBy(if (compact) 10.dp else 22.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = model::toggleShuffle, modifier = Modifier.size(44.dp)) {
            Icon(
                Icons.Default.Shuffle,
                "Перемешать",
                tint = Color.White.copy(alpha = if (model.shuffle) 1f else .55f),
            )
        }
        IconButton(
            onClick = model::previous,
            modifier = Modifier.size(if (compact) 46.dp else 54.dp),
        ) {
            Icon(Icons.Default.FastRewind, "Предыдущий нашид", Modifier.size(32.dp))
        }
        Box(contentAlignment = Alignment.Center) {
            FilledIconButton(
                onClick = model::toggle,
                modifier = Modifier.size(playSize).testTag("player.toggle"),
                colors =
                    IconButtonDefaults.filledIconButtonColors(
                        containerColor = Color.White,
                        contentColor = Color.Black,
                    ),
            ) {
                Icon(
                    if (model.playing) Icons.Default.Pause else Icons.Default.PlayArrow,
                    if (model.playing) "Пауза" else "Воспроизвести",
                    Modifier.size(34.dp),
                )
            }
            if (model.buffering) {
                val ring = Modifier.size(playSize + 10.dp).clearAndSetSemantics {}
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
        IconButton(onClick = model::next, modifier = Modifier.size(if (compact) 46.dp else 54.dp)) {
            Icon(Icons.Default.FastForward, "Следующий нашид", Modifier.size(32.dp))
        }
        IconButton(onClick = model::cycleRepeat, modifier = Modifier.size(44.dp)) {
            Icon(
                if (model.repeat == Player.REPEAT_MODE_ONE) Icons.Default.RepeatOne
                else Icons.Default.Repeat,
                "Повтор",
                tint =
                    Color.White.copy(
                        alpha = if (model.repeat == Player.REPEAT_MODE_OFF) .55f else 1f
                    ),
            )
        }
    }
}

@Composable
internal fun AudioOutputButton() {
    val context = LocalContext.current
    PlayerAction(
        MuwaSymbols.AudioOutput,
        "Аудиовыход",
        {
            runCatching {
                    val shown =
                        Build.VERSION.SDK_INT >= 34 &&
                            MediaRouter2.getInstance(context).showSystemOutputSwitcher()
                    if (!shown)
                        context.startActivity(
                            Intent(
                                if (Build.VERSION.SDK_INT >= 29) Settings.Panel.ACTION_VOLUME
                                else Settings.ACTION_BLUETOOTH_SETTINGS
                            )
                        )
                }
                .onFailure { Diagnostics.record("audio-output", it) }
        },
        Modifier.testTag("player.output"),
    )
}

@Composable
internal fun PlayerMenu(
    model: MuwaModel,
    hasLyrics: Boolean,
    lyricsVisible: Boolean,
    toggleLyrics: () -> Unit,
    onPlaylist: () -> Unit,
) {
    val track = model.track ?: return
    val context = LocalContext.current
    var menu by remember { mutableStateOf(false) }
    var timerMenu by remember { mutableStateOf(false) }
    Box {
        PlayerAction(
            Icons.Default.MoreVert,
            "Меню плеера",
            { menu = true },
            Modifier.testTag("player.menu"),
            42.dp,
        )
        DropdownMenu(
            menu,
            {
                menu = false
                timerMenu = false
            },
            containerColor = MuwaColors.Surface,
        ) {
            if (timerMenu) {
                DropdownMenuItem(text = { Text("Назад") }, onClick = { timerMenu = false })
                listOf(15, 30, 45, 60).forEach { minutes ->
                    DropdownMenuItem(
                        text = { Text("$minutes минут") },
                        onClick = {
                            SleepTimer.start(minutes)
                            menu = false
                            timerMenu = false
                        },
                    )
                }
                DropdownMenuItem(
                    text = { Text("После текущего нашида") },
                    onClick = {
                        SleepTimer.afterCurrent()
                        menu = false
                        timerMenu = false
                    },
                )
                if (SleepTimer.endAt != null || SleepTimer.afterTrack)
                    DropdownMenuItem(
                        text = { Text("Выключить таймер") },
                        onClick = {
                            SleepTimer.cancel()
                            menu = false
                            timerMenu = false
                        },
                    )
            } else {
                DropdownMenuItem(
                    text = { Text(if (lyricsVisible) "Скрыть субтитры" else "Показать субтитры") },
                    leadingIcon = { Icon(MuwaSymbols.Captions, null) },
                    enabled = hasLyrics,
                    onClick = {
                        toggleLyrics()
                        menu = false
                    },
                )
                HorizontalDivider()
                DropdownMenuItem(
                    text = {
                        Text(
                            if (track.id in model.library.favorites) "Убрать из избранного"
                            else "Добавить в избранное"
                        )
                    },
                    leadingIcon = { Icon(Icons.Default.FavoriteBorder, null) },
                    onClick = {
                        model.library.like(track)
                        menu = false
                    },
                )
                DropdownMenuItem(
                    text = { Text("Добавить в плей-лист") },
                    leadingIcon = { Icon(Icons.AutoMirrored.Filled.PlaylistAdd, null) },
                    onClick = {
                        onPlaylist()
                        menu = false
                    },
                )
                DropdownMenuItem(
                    text = { Text("Этот нашид уже играет") },
                    enabled = false,
                    onClick = {},
                )
                DropdownMenuItem(text = { Text("Уже в очереди") }, enabled = false, onClick = {})
                DropdownMenuItem(
                    text = { Text("Таймер сна") },
                    leadingIcon = { Icon(Icons.Default.Bedtime, null) },
                    onClick = { timerMenu = true },
                )
                HorizontalDivider()
                val downloaded = track.id in model.downloads.downloaded
                val downloading = model.downloads.progress.containsKey(track.id)
                DropdownMenuItem(
                    text = {
                        Text(
                            if (downloaded) "Сохранено офлайн"
                            else if (downloading) "Скачиваем…" else "Скачать офлайн"
                        )
                    },
                    leadingIcon = {
                        Icon(
                            if (downloaded) Icons.Default.CheckCircleOutline
                            else Icons.Default.Download,
                            null,
                        )
                    },
                    enabled = !downloaded && !downloading,
                    onClick = {
                        model.downloads.download(track) { model.error = it.message }
                        menu = false
                    },
                )
                if (downloaded || downloading)
                    DropdownMenuItem(
                        text = {
                            Text(
                                if (downloaded) "Удалить загрузку" else "Отменить скачивание",
                                color = Color(0xFFFF6868),
                            )
                        },
                        leadingIcon = {
                            Icon(Icons.Default.DeleteOutline, null, tint = Color(0xFFFF6868))
                        },
                        onClick = {
                            menu = false
                            runCatching {
                                    if (downloaded) model.downloads.remove(track)
                                    else model.downloads.cancel(track)
                                }
                                .onFailure { model.error = it.message }
                        },
                    )
                DropdownMenuItem(
                    text = { Text("Поделиться нашидом") },
                    leadingIcon = { Icon(Icons.Default.IosShare, null) },
                    onClick = {
                        menu = false
                        runCatching {
                                context.startActivity(
                                    Intent.createChooser(
                                        Intent(Intent.ACTION_SEND)
                                            .setType("text/plain")
                                            .putExtra(
                                                Intent.EXTRA_TEXT,
                                                "${track.title}\n${track.audio}",
                                            ),
                                        "Поделиться нашидом",
                                    )
                                )
                            }
                            .onFailure { model.error = it.message }
                    },
                )
            }
        }
    }
}
