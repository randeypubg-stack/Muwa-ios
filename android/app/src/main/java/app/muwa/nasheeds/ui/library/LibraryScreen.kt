package app.muwa.nasheeds.ui.library

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
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.components.*
import app.muwa.nasheeds.ui.design.*

@Composable
fun LibraryScreen(model: MuwaModel, onRoute: (String) -> Unit, onCreatePlaylist: () -> Unit) {
    LazyColumn(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { ActionCard("Избранное", Icons.Default.Favorite) { onRoute("favorites") } }
        item { ActionCard("Недавно прослушано", Icons.Default.History) { onRoute("history") } }
        item { ActionCard("Загрузки", Icons.Default.Download) { onRoute("downloads") } }
        item { ActionCard("Очередь", Icons.AutoMirrored.Filled.QueueMusic) { onRoute("queue") } }
        item { ActionCard("Опубликовать нашид", Icons.Default.Upload) { onRoute("publication") } }
        item {
            Text("Мои плейлисты", style = MaterialTheme.typography.titleLarge)
            TextButton(onClick = { onCreatePlaylist() }) { Text("Создать плейлист") }
        }
        items(model.library.playlists, key = { it.id }) { playlist ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(
                    onClick = { onRoute("playlist:${playlist.id}") },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("${playlist.name} · ${playlist.ids.size}")
                }
                IconButton(onClick = { model.library.deletePlaylist(playlist.id) }) {
                    Icon(Icons.Default.Delete, "Удалить плейлист")
                }
            }
        }
    }
}
