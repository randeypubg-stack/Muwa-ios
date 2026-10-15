package app.muwa.nasheeds.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.Track
import app.muwa.nasheeds.ui.components.Cover
import app.muwa.nasheeds.ui.components.TrackRow
import app.muwa.nasheeds.ui.components.trackCount
import app.muwa.nasheeds.ui.design.MuwaAdaptiveLayout
import app.muwa.nasheeds.ui.design.MuwaColors

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun HomeScreen(
    model: MuwaModel,
    play: (Track) -> Unit,
    playlist: (Track) -> Unit,
    onCollection: (String) -> Unit,
    resume: () -> Unit,
    openPlayer: (Track) -> Unit,
    openResume: () -> Unit,
) {
    val catalog = model.library.catalog
    val smallestWidth = LocalConfiguration.current.smallestScreenWidthDp
    BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        val layout = MuwaAdaptiveLayout(maxWidth.value, maxHeight.value, smallestWidth)
        LazyColumn(
            Modifier.widthIn(max = 1180.dp).fillMaxSize().testTag("home.screen"),
            contentPadding = PaddingValues(horizontal = layout.homePadding.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            val saved = model.resumeCandidate
            val resumeTrack = saved?.let { model.library.track(it.first) }
            if (saved != null && resumeTrack != null && model.track == null)
                item {
                    Column(
                        Modifier.fillMaxWidth()
                            .background(Color.White.copy(alpha = .025f), RoundedCornerShape(22.dp))
                            .border(1.dp, Color.White.copy(alpha = .05f), RoundedCornerShape(22.dp))
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "ПРОДОЛЖИТЬ СЛУШАТЬ",
                                Modifier.weight(1f),
                                fontSize = 10.sp,
                                lineHeight = 14.sp,
                                letterSpacing = 2.sp,
                                fontWeight = FontWeight.Bold,
                                color = MuwaColors.Secondary,
                            )
                            IconButton(
                                onClick = model::dismissResume,
                                modifier = Modifier.size(32.dp),
                            ) {
                                Icon(
                                    androidx.compose.material.icons.Icons.Default.Close,
                                    "Скрыть предложение продолжить",
                                    Modifier.size(14.dp),
                                )
                            }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Cover(
                                resumeTrack,
                                Modifier.size(82.dp).clickable(onClick = openResume),
                                19.dp,
                            )
                            Column(
                                Modifier.weight(1f).padding(start = 12.dp),
                                verticalArrangement = Arrangement.spacedBy(5.dp),
                            ) {
                                Text(
                                    resumeTrack.title,
                                    fontSize = 16.sp,
                                    lineHeight = 21.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(
                                    resumeTrack.artist,
                                    fontSize = 12.sp,
                                    lineHeight = 16.sp,
                                    color = MuwaColors.Secondary,
                                    maxLines = 1,
                                )
                                Text(
                                    app.muwa.nasheeds.formatTime(saved.second),
                                    fontSize = 11.sp,
                                    lineHeight = 14.sp,
                                    color = MuwaColors.Secondary,
                                )
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button(
                                        onClick = resume,
                                        colors =
                                            ButtonDefaults.buttonColors(
                                                containerColor = Color.White,
                                                contentColor = Color.Black,
                                            ),
                                        contentPadding =
                                            PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                                    ) {
                                        Text("Продолжить", fontSize = 11.sp)
                                    }
                                    TextButton(
                                        onClick = openResume,
                                        contentPadding =
                                            PaddingValues(horizontal = 10.dp, vertical = 6.dp),
                                    ) {
                                        Text("Открыть", fontSize = 11.sp)
                                    }
                                }
                            }
                        }
                    }
                }
            item {
                Text(
                    "Нашиды без музыки",
                    color = MuwaColors.Secondary,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "В вашем ритме",
                            style = MaterialTheme.typography.titleLarge,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = { onCollection("all") }) {
                            Text("Все")
                            Icon(Icons.Default.NorthEast, null, Modifier.size(15.dp))
                        }
                    }
                    BoxWithConstraints {
                        val vertical = maxWidth < 300.dp || LocalDensity.current.fontScale > 1.3f
                        val cards: @Composable RowScope.() -> Unit = {
                            val short = catalog.filter { it.duration <= 180 }
                            val long = catalog.filter { it.duration > 180 }
                            if (short.isNotEmpty())
                                CollectionCard(
                                    "На несколько минут",
                                    "До 3 минут",
                                    Icons.Default.AccessTime,
                                    MuwaColors.Blue,
                                    short,
                                    Modifier.weight(1f),
                                ) {
                                    onCollection("short")
                                }
                            if (long.isNotEmpty())
                                CollectionCard(
                                    "Слушать подольше",
                                    "Больше 3 минут",
                                    Icons.Default.Headphones,
                                    MuwaColors.Teal,
                                    long,
                                    Modifier.weight(1f),
                                ) {
                                    onCollection("long")
                                }
                        }
                        if (vertical)
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                val short = catalog.filter { it.duration <= 180 }
                                val long = catalog.filter { it.duration > 180 }
                                if (short.isNotEmpty())
                                    CollectionCard(
                                        "На несколько минут",
                                        "До 3 минут",
                                        Icons.Default.AccessTime,
                                        MuwaColors.Blue,
                                        short,
                                        Modifier.fillMaxWidth(),
                                    ) {
                                        onCollection("short")
                                    }
                                if (long.isNotEmpty())
                                    CollectionCard(
                                        "Слушать подольше",
                                        "Больше 3 минут",
                                        Icons.Default.Headphones,
                                        MuwaColors.Teal,
                                        long,
                                        Modifier.fillMaxWidth(),
                                    ) {
                                        onCollection("long")
                                    }
                            }
                        else
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                                content = cards,
                            )
                    }
                }
            }
            if (catalog.isNotEmpty())
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text("Откройте для себя", style = MaterialTheme.typography.titleLarge)
                        Box {
                            if (layout.wideTablet) {
                                val count = layout.recommendationColumns
                                Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
                                    catalog.take(12).chunked(count).forEach { row ->
                                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                                            row.forEach { track ->
                                                RecommendationCard(track, Modifier.weight(1f)) {
                                                    openPlayer(track)
                                                }
                                            }
                                            repeat(count - row.size) { Spacer(Modifier.weight(1f)) }
                                        }
                                    }
                                }
                            } else
                                LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                                    items(catalog.take(12), key = { it.id }) { track ->
                                        RecommendationCard(track, Modifier.width(160.dp)) {
                                            openPlayer(track)
                                        }
                                    }
                                }
                        }
                    }
                }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Популярное", style = MaterialTheme.typography.titleLarge)
                    if (catalog.size > 5)
                        Text(
                            "Листайте, чтобы открыть больше нашидов",
                            color = MuwaColors.Secondary,
                            fontSize = 12.sp,
                            lineHeight = 16.sp,
                        )
                }
            }
            item {
                BoxWithConstraints {
                    val pageWidth = maxWidth
                    val pages = rememberLazyListState()
                    LazyRow(
                        state = pages,
                        flingBehavior = rememberSnapFlingBehavior(pages),
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        modifier = Modifier.testTag("popular.pages"),
                    ) {
                        items(catalog.chunked(layout.popularPageSize), key = { it.first().id }) {
                            page ->
                            Column(
                                Modifier.width(pageWidth).testTag("popular.page.${page.first().id}")
                            ) {
                                page.chunked(layout.popularColumns).forEach { row ->
                                    Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                                        row.forEach { track ->
                                            Column(Modifier.weight(1f)) {
                                                TrackRow(model, track, play, playlist)
                                                HorizontalDivider(
                                                    color = Color.White.copy(alpha = .05f)
                                                )
                                            }
                                        }
                                        repeat(layout.popularColumns - row.size) {
                                            Spacer(Modifier.weight(1f))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CollectionCard(
    title: String,
    detail: String,
    icon: ImageVector,
    tint: Color,
    tracks: List<Track>,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(26.dp)
    Card(
        onClick = onClick,
        modifier =
            modifier.border(
                .75.dp,
                Brush.linearGradient(
                    listOf(Color.White.copy(alpha = .19f), Color.White.copy(alpha = .025f))
                ),
                shape,
            ),
        shape = shape,
        colors = CardDefaults.cardColors(containerColor = Color.Transparent),
    ) {
        Column(
            Modifier.background(
                    Brush.linearGradient(
                        listOf(tint.copy(alpha = .18f), MuwaColors.Surface.copy(alpha = .85f))
                    )
                )
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Box(
                    Modifier.size(38.dp).background(Color.White.copy(alpha = .08f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(icon, null, Modifier.size(18.dp), tint = MuwaColors.Ice)
                }
                Box(Modifier.size(62.dp, 66.dp)) {
                    tracks.getOrNull(1)?.let {
                        Cover(
                            it,
                            Modifier.size(56.dp).graphicsLayer {
                                rotationZ = 12f
                                translationX = 7.dp.toPx()
                                translationY = 6.dp.toPx()
                                alpha = .55f
                            },
                        )
                    }
                    Cover(tracks.first(), Modifier.size(56.dp).graphicsLayer { rotationZ = -8f })
                }
            }
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.heightIn(min = 60.dp),
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom,
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(detail, color = MuwaColors.Secondary, fontSize = 12.sp)
                    Text(
                        trackCount(tracks.size),
                        color = MuwaColors.Secondary,
                        fontSize = 11.sp,
                        lineHeight = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                Icon(Icons.Default.NorthEast, null, Modifier.size(15.dp), tint = MuwaColors.Ice)
            }
        }
    }
}

@Composable
private fun RecommendationCard(track: Track, modifier: Modifier, play: () -> Unit) {
    Column(modifier.clickable(onClick = play), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Cover(track, Modifier.fillMaxWidth().aspectRatio(1f), 28.dp)
        Text(
            track.title,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            track.artist,
            color = MuwaColors.Secondary,
            fontSize = 12.sp,
            lineHeight = 16.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
