package app.muwa.nasheeds.ui.player

import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.design.*
import coil.compose.AsyncImage
import coil.request.ImageRequest

/** Shares the Activity viewport and the root's approved bottom anchor with iOS. */
@Composable
fun PlayerSheet(
    model: MuwaModel,
    onClose: () -> Unit,
    onQueue: () -> Unit,
    onSubtitles: () -> Unit,
    onPlaylist: () -> Unit,
    bottomClearance: Dp,
) {
    val track = model.track ?: return
    var lyricsVisible by
        rememberSaveable(track.id, track.audio, track.captionsRevision) { mutableStateOf(false) }
    LaunchedEffect(track.id, track.audio, track.captionsRevision) { model.loadSubtitles() }
    val hasLyrics = model.subtitles.any { it.optString("ar").isNotBlank() }
    val close by rememberUpdatedState(onClose)
    BoxWithConstraints(
        Modifier.fillMaxSize()
            .testTag("player.screen")
            .background(Color.Black)
            .clipToBounds()
            .pointerInput(Unit) { detectTapGestures {} }
    ) {
        val density = LocalDensity.current
        val insets = WindowInsets.safeDrawing
        val top = with(density) { insets.getTop(this).toDp() }
        val left =
            with(density) {
                insets.getLeft(this, androidx.compose.ui.unit.LayoutDirection.Ltr).toDp()
            }
        val right =
            with(density) {
                insets.getRight(this, androidx.compose.ui.unit.LayoutDirection.Ltr).toDp()
            }
        val bodyHeight =
            maxHeight - top - bottomClearance - BottomNavigationLayout.barHeightDp.dp - 8.dp
        val width = maxWidth - left - right
        val landscape = width > maxHeight * 1.2f && maxHeight < 600.dp
        val tablet = minOf(maxWidth, maxHeight) >= 600.dp
        val short = !tablet && maxHeight - top < 740.dp
        val compactLandscape = landscape && bodyHeight < 260.dp
        var controlsHeight by remember { mutableIntStateOf(0) }
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current).data(track.artwork).size(96).build(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            colorFilter = ColorFilter.colorMatrix(ColorMatrix().apply { setToSaturation(.85f) }),
            alpha = .34f,
            modifier = Modifier.fillMaxSize().blur(64.dp),
        )
        Box(
            Modifier.fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = .16f),
                            Color.Black.copy(alpha = .56f),
                            Color.Black,
                        )
                    )
                )
        )
        Column(
            Modifier.padding(start = left + 5.dp, end = right + 5.dp, top = top)
                .height(bodyHeight)
                .fillMaxWidth()
                .testTag("player.safe-content")
        ) {
            Row(
                Modifier.fillMaxWidth().height(if (compactLandscape) 48.dp else 56.dp).pointerInput(
                    Unit
                ) {
                    var distance = 0f
                    detectVerticalDragGestures(
                        onDragStart = { distance = 0f },
                        onDragEnd = { if (distance > 40.dp.toPx()) close() },
                    ) { change, amount ->
                        distance += amount
                        change.consume()
                    }
                },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                PlayerAction(
                    Icons.Default.KeyboardArrowDown,
                    "Закрыть плеер",
                    onClose,
                    Modifier.testTag("player.close"),
                    42.dp,
                )
                Text(
                    "Сейчас играет",
                    Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    color = MuwaColors.Secondary,
                )
                PlayerMenu(
                    model,
                    hasLyrics,
                    lyricsVisible,
                    { lyricsVisible = !lyricsVisible },
                    onPlaylist,
                )
            }
            val controls: @Composable (Modifier) -> Unit = { modifier ->
                Column(
                    modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    PlayerMetadata(model, compact = landscape)
                    Spacer(Modifier.height(if (landscape) 0.dp else if (short) 14.dp else 32.dp))
                    PlayerScrubber(model, compact = landscape)
                    Spacer(Modifier.height(if (landscape) 0.dp else if (short) 18.dp else 30.dp))
                    PlayerTransport(
                        model,
                        compact = !tablet || landscape,
                        shortWindow = compactLandscape,
                    )
                    Spacer(Modifier.height(if (landscape) 0.dp else if (short) 14.dp else 22.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        PlayerAction(
                            MuwaSymbols.Captions,
                            if (lyricsVisible) "Скрыть субтитры" else "Показать субтитры",
                            { lyricsVisible = !lyricsVisible },
                            Modifier.testTag("player.subtitles"),
                            enabled = hasLyrics,
                            active = lyricsVisible,
                        )
                        PlayerAction(
                            Icons.AutoMirrored.Filled.FormatListBulleted,
                            "Открыть очередь",
                            onQueue,
                            Modifier.testTag("player.queue"),
                        )
                        AudioOutputButton()
                    }
                    model.downloads.progress[track.id]?.let {
                        LinearProgressIndicator(
                            progress = { it },
                            modifier = Modifier.padding(top = 6.dp).width(170.dp),
                        )
                    }
                    if (model.error != null)
                        TextButton(onClick = model::retry) {
                            Text("Не удалось воспроизвести · Повторить", fontSize = 11.sp)
                        }
                }
            }
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                // Fixed touch sizes, flexible artwork and gaps: large text may scroll
                // the body, while the navigation anchor remains owned by the root.
                val limit =
                    if (tablet) minOf(420.dp, width * .68f, maxHeight * .62f)
                    else minOf(if (short) 210.dp else 310.dp, width * .68f)
                val coverSize =
                    if (landscape) minOf(maxHeight - 12.dp, width * .39f).coerceAtLeast(60.dp)
                    else
                        minOf(
                                limit,
                                maxHeight -
                                    with(density) { controlsHeight.toDp() } -
                                    (if (short) 16.dp else 26.dp) -
                                    28.dp,
                            )
                            .coerceAtLeast(60.dp)
                if (landscape)
                    Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(.44f), contentAlignment = Alignment.Center) {
                            PlayerArtworkAndLyrics(
                                model,
                                coverSize,
                                lyricsVisible && hasLyrics,
                                onClose,
                                onSubtitles,
                            )
                        }
                        controls(
                            Modifier.weight(.56f)
                                .fillMaxHeight()
                                .verticalScroll(rememberScrollState())
                        )
                    }
                else
                    Column(
                        Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Spacer(Modifier.height(if (short) 0.dp else 2.dp))
                        PlayerArtworkAndLyrics(
                            model,
                            coverSize,
                            lyricsVisible && hasLyrics,
                            onClose,
                            onSubtitles,
                        )
                        Spacer(Modifier.height(if (short) 16.dp else 24.dp))
                        controls(Modifier.onSizeChanged { controlsHeight = it.height })
                        Spacer(Modifier.height(24.dp))
                    }
            }
        }
    }
}
