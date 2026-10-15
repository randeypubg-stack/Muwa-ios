package app.muwa.nasheeds.ui.library

import android.content.Context
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.ui.components.Cover
import app.muwa.nasheeds.ui.design.*

@Composable
internal fun LibraryCollectionsScreen(
    model: MuwaModel,
    route: String,
    onRoute: (String) -> Unit,
    create: () -> Unit,
) {
    val prefs = LocalContext.current.getSharedPreferences("muwa.publication", Context.MODE_PRIVATE)
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (route == "playlists") {
            item { Text("Ваши нашиды, собранные по настроению", color = MuwaColors.Secondary) }
            item {
                OutlinedButton(onClick = create, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.Add, null)
                    Text("Создать плейлист")
                }
            }
            if (model.library.playlists.isEmpty())
                item {
                    LibraryEmpty(
                        "Соберите свою подборку",
                        "Для дороги, спокойного вечера или любимых нашидов — всё в одном плейлисте.",
                    )
                }
            items(model.library.playlists, key = { it.id }) { playlist ->
                var menu by remember { mutableStateOf(false) }
                Row(
                    Modifier.fillMaxWidth().glassPanel(23.dp).padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Row(
                        Modifier.weight(1f).clickable { onRoute("playlist:${playlist.id}") },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        val first = model.library.tracks(playlist.ids).firstOrNull()
                        if (first != null) Cover(first, Modifier.size(72.dp), 18.dp)
                        else
                            Icon(Icons.AutoMirrored.Filled.PlaylistPlay, null, Modifier.size(56.dp))
                        Column(Modifier.padding(start = 16.dp)) {
                            Text(playlist.name, fontWeight = FontWeight.Bold)
                            Text(
                                "${playlist.ids.size} нашидов",
                                fontSize = 12.sp,
                                lineHeight = 16.sp,
                                color = MuwaColors.Secondary,
                            )
                        }
                    }
                    Box {
                        IconButton(onClick = { menu = true }) {
                            Icon(Icons.Default.MoreVert, "Действия плей-листа")
                        }
                        DropdownMenu(menu, { menu = false }) {
                            DropdownMenuItem(
                                text = { Text("Удалить плей-лист") },
                                leadingIcon = { Icon(Icons.Default.DeleteOutline, null) },
                                onClick = {
                                    model.library.deletePlaylist(playlist.id)
                                    menu = false
                                },
                            )
                        }
                    }
                }
            }
        } else if (route == "drafts") {
            item { Text("Незавершённые публикации", color = MuwaColors.Secondary) }
            val title = prefs.getString("title", "").orEmpty()
            if (title.isNotBlank() && prefs.getString("status", "") != "Отправлено на модерацию")
                item {
                    Column(
                        Modifier.fillMaxWidth()
                            .glassPanel()
                            .clickable { onRoute("publication") }
                            .padding(20.dp)
                    ) {
                        Text(title, fontWeight = FontWeight.Bold)
                        Text("Продолжить публикацию", color = MuwaColors.Secondary)
                    }
                }
            else item { LibraryEmpty("Черновиков нет", "Здесь появятся незавершённые публикации.") }
        } else {
            item { Text("Статусы отправленных публикаций", color = MuwaColors.Secondary) }
            if (model.library.publications.isEmpty())
                item {
                    LibraryEmpty(
                        "Публикаций пока нет",
                        "Добавьте нашид, чтобы отправить его на проверку.",
                    )
                }
            items(model.library.publications) { publication ->
                Column(
                    Modifier.fillMaxWidth().glassPanel().padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(publication.optString("title"), fontWeight = FontWeight.Bold)
                    Text(
                        publication.optString("artist"),
                        color = MuwaColors.Secondary,
                        fontSize = 12.sp,
                        lineHeight = 16.sp,
                    )
                    Text("Отправлено на модерацию", color = MuwaColors.Ice, fontSize = 12.sp)
                }
            }
            item {
                TextButton(
                    onClick = { onRoute(if (model.user == null) "auth" else "publication") }
                ) {
                    Text("Добавить нашид")
                }
            }
        }
    }
}

@Composable
private fun LibraryEmpty(title: String, detail: String) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Default.LibraryMusic, null, Modifier.size(44.dp), tint = MuwaColors.Secondary)
        Text(title, style = MaterialTheme.typography.titleLarge)
        Text(
            detail,
            color = MuwaColors.Secondary,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}
