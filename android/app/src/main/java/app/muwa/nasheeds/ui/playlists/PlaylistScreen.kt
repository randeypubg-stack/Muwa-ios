package app.muwa.nasheeds.ui.playlists

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.Track
import app.muwa.nasheeds.ui.components.*
import app.muwa.nasheeds.ui.design.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PlaylistScreen(
    model: MuwaModel,
    id: String,
    play: (Track, List<Track>) -> Unit,
    addToPlaylist: (Track) -> Unit,
) {
    val list = model.library.playlists.firstOrNull { it.id == id }
    var picker by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var name by remember(list?.name) { mutableStateOf(list?.name.orEmpty()) }
    val tracks = model.library.tracks(list?.ids.orEmpty())
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(list?.name.orEmpty(), style = MaterialTheme.typography.headlineLarge)
            Text(trackCount(tracks.size), color = MuwaColors.Secondary)
            Row {
                TextButton(
                    onClick = { picker = true },
                    modifier = Modifier.testTag("playlist.add"),
                ) {
                    Icon(Icons.Default.Add, null)
                    Text("Добавить нашиды")
                }
                TextButton(onClick = { renaming = true }) { Text("Переименовать") }
            }
        }
        if (tracks.isEmpty())
            item {
                EmptyState(
                    Icons.Default.MusicNote,
                    "Добавьте первые нашиды",
                    "Соберите свою подборку из каталога Muwa.",
                    "Добавить нашиды",
                    { picker = true },
                )
            }
        items(tracks, key = { it.id }) { track ->
            TrackRow(model, track, { play(it, tracks) }, addToPlaylist)
            TextButton(onClick = { model.library.togglePlaylist(id, track) }) {
                Icon(Icons.Default.RemoveCircleOutline, null)
                Spacer(Modifier.width(8.dp))
                Text("Убрать из плейлиста")
            }
        }
    }
    if (renaming)
        AlertDialog(
            onDismissRequest = { renaming = false },
            title = { Text("Название плей-листа") },
            text = { OutlinedTextField(name, { name = it }, singleLine = true) },
            confirmButton = {
                TextButton(
                    onClick = {
                        model.library.renamePlaylist(id, name)
                        renaming = false
                    },
                    enabled = name.isNotBlank(),
                ) {
                    Text("Сохранить")
                }
            },
            dismissButton = { TextButton(onClick = { renaming = false }) { Text("Отмена") } },
        )
    if (picker)
        ModalBottomSheet(
            onDismissRequest = { picker = false },
            containerColor = MuwaColors.Background,
        ) {
            var query by remember { mutableStateOf("") }
            Column(Modifier.fillMaxHeight(.85f).padding(horizontal = 20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "Добавить нашиды",
                        Modifier.weight(1f),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    TextButton(onClick = { picker = false }) { Text("Готово") }
                }
                OutlinedTextField(
                    query,
                    { query = it },
                    placeholder = { Text("Название или автор") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                LazyColumn {
                    items(
                        model.library.catalog.filter {
                            it.title.contains(query.trim(), true) ||
                                it.artist.contains(query.trim(), true)
                        },
                        key = { it.id },
                    ) { track ->
                        val selected =
                            model.library.playlists
                                .firstOrNull { it.id == id }
                                ?.ids
                                ?.contains(track.id) == true
                        Row(
                            Modifier.fillMaxWidth()
                                .testTag("playlist.pick.${track.id}")
                                .clickable { model.library.togglePlaylist(id, track) }
                                .padding(vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Cover(track, Modifier.size(44.dp), 13.dp)
                            Text(
                                track.title,
                                Modifier.weight(1f).padding(horizontal = 12.dp),
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Icon(
                                if (selected) Icons.Default.CheckCircle
                                else Icons.Default.RadioButtonUnchecked,
                                if (selected) "Добавлен" else "Добавить",
                                tint = if (selected) MuwaColors.Ice else MuwaColors.Secondary,
                            )
                        }
                    }
                }
            }
        }
}
