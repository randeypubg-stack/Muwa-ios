package app.muwa.nasheeds.ui.library

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.design.*

@Composable
fun LibraryScreen(model: MuwaModel, onRoute: (String) -> Unit, onCreatePlaylist: () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val columns = if (maxWidth >= 700.dp) 4 else if (maxWidth >= 560.dp) 3 else 2
        val outer = if (maxWidth >= 700.dp) 28.dp else 5.dp
        LazyColumn(
            Modifier.widthIn(max = 1180.dp).align(Alignment.TopCenter).fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = outer, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item {
                Row(
                    Modifier.fillMaxWidth().glassPanel().padding(17.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        Modifier.size(54.dp).glassPanel(19.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.AutoMirrored.Filled.LibraryBooks, null, Modifier.size(26.dp))
                    }
                    Column(Modifier.weight(1f).padding(start = 14.dp)) {
                        Text("Ваша библиотека", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                        Text(
                            "Всё сохранённое в одном месте",
                            fontSize = 12.sp,
                            color = MuwaColors.Secondary,
                        )
                    }
                    Icon(Icons.Default.AutoAwesome, null, tint = Color.White.copy(alpha = .28f))
                }
            }
            item {
                Button(
                    onClick = { onRoute(if (model.user == null) "auth" else "publication") },
                    modifier = Modifier.fillMaxWidth().height(50.dp).testTag("library.publish"),
                    shape = androidx.compose.foundation.shape.RoundedCornerShape(18.dp),
                    colors =
                        ButtonDefaults.buttonColors(
                            containerColor = Color.White,
                            contentColor = Color.Black,
                        ),
                ) {
                    Icon(Icons.Default.Add, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Добавить нашид", fontWeight = FontWeight.Bold)
                }
            }
            item {
                val tiles =
                    listOf(
                        LibraryTile(
                            "favorites",
                            "Избранные",
                            Icons.Default.Favorite,
                            model.library.favorites.size,
                            Color(0xFFFF6B97),
                        ),
                        LibraryTile(
                            "history",
                            "Недавно прослушано",
                            Icons.Default.History,
                            model.library.history.size,
                            MuwaColors.Blue,
                        ),
                        LibraryTile(
                            "playlists",
                            "Мои плей-листы",
                            Icons.AutoMirrored.Filled.PlaylistPlay,
                            model.library.playlists.size,
                            Color.Cyan,
                        ),
                        LibraryTile(
                            "publications",
                            "Мои публикации",
                            Icons.Default.IosShare,
                            model.library.publications.size,
                            MuwaColors.Teal,
                        ),
                    )
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    tiles.chunked(columns).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            row.forEach { tile ->
                                LibraryTileCard(tile, Modifier.weight(1f)) { onRoute(tile.route) }
                            }
                            repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
            item { Text("Быстрый доступ", style = MaterialTheme.typography.titleMedium) }
            item {
                QuickAccess(
                    "Черновики публикаций",
                    "Незавершённые публикации",
                    Icons.Default.Description,
                ) {
                    onRoute("drafts")
                }
            }
            item {
                QuickAccess(
                    "Загрузки",
                    if (model.downloads.downloaded.isEmpty()) "Офлайн-сохранения появятся здесь"
                    else "${model.downloads.downloaded.size} сохранено офлайн",
                    Icons.Default.DownloadForOffline,
                ) {
                    onRoute("downloads")
                }
            }
        }
    }
}

private data class LibraryTile(
    val route: String,
    val title: String,
    val icon: ImageVector,
    val count: Int,
    val tint: Color,
)

@Composable
private fun LibraryTileCard(tile: LibraryTile, modifier: Modifier, click: () -> Unit) {
    Column(
        modifier
            .glassPanel(23.dp)
            .clickable(onClick = click)
            .background(
                Brush.radialGradient(listOf(tile.tint.copy(alpha = .12f), Color.Transparent))
            )
            .padding(15.dp)
            .heightIn(min = 126.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Icon(tile.icon, null, tint = tile.tint, modifier = Modifier.size(22.dp))
            Text(
                "${tile.count}",
                Modifier.glassPanel(20.dp).padding(horizontal = 7.dp, vertical = 3.dp),
                fontSize = 10.sp,
                color = MuwaColors.Secondary,
            )
        }
        Spacer(Modifier.height(8.dp))
        Text(tile.title, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        Text("Открыть раздел", fontSize = 11.sp, color = MuwaColors.Secondary)
    }
}

@Composable
private fun QuickAccess(title: String, subtitle: String, icon: ImageVector, click: () -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .glassPanel(20.dp)
            .clickable(onClick = click)
            .padding(15.dp)
            .heightIn(min = 40.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(23.dp))
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Text(subtitle, fontSize = 11.sp, color = MuwaColors.Secondary)
        }
        Icon(Icons.Default.ChevronRight, null, tint = MuwaColors.Secondary)
    }
}
