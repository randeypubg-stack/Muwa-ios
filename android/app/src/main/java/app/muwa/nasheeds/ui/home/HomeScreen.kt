package app.muwa.nasheeds.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
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
import app.muwa.nasheeds.ui.design.MuwaColors

@Composable
fun HomeScreen(
    model: MuwaModel,
    play: (Track) -> Unit,
    playlist: (Track) -> Unit,
    onCollection: (String) -> Unit,
    resume: () -> Unit,
    openPlayer: (Track) -> Unit,
) {
    val catalog = model.library.catalog
    LazyColumn(
        Modifier.fillMaxSize().testTag("home.screen"),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        if (model.resumeCandidate != null && model.track == null)
            item {
                Card(
                    colors =
                        CardDefaults.cardColors(containerColor = MuwaColors.Ice.copy(alpha = .07f)),
                    shape = RoundedCornerShape(24.dp),
                ) {
                    Column(Modifier.padding(18.dp)) {
                        Text(
                            "Продолжить прослушивание",
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Row {
                            TextButton(onClick = resume) { Text("Продолжить") }
                            TextButton(onClick = model::dismissResume) { Text("Скрыть") }
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
                    else Row(horizontalArrangement = Arrangement.spacedBy(12.dp), content = cards)
                }
            }
        }
        if (catalog.isNotEmpty())
            item {
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("Откройте для себя", style = MaterialTheme.typography.titleLarge)
                    BoxWithConstraints {
                        if (maxWidth >= 660.dp) {
                            val count = if (maxWidth >= 960.dp) 4 else 3
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
                    )
            }
        }
        item {
            BoxWithConstraints {
                val pageWidth = maxWidth
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    modifier = Modifier.testTag("popular.pages"),
                ) {
                    items(
                        catalog.chunked(if (pageWidth >= 660.dp) 6 else 5),
                        key = { it.first().id },
                    ) { page ->
                        Column(
                            Modifier.width(pageWidth).testTag("popular.page.${page.first().id}")
                        ) {
                            page.forEach {
                                TrackRow(model, it, play, playlist)
                                HorizontalDivider(color = Color.White.copy(alpha = .05f))
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
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
