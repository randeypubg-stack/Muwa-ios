package app.muwa.nasheeds.ui.playlists

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.Track
import app.muwa.nasheeds.ui.components.TrackRow

@Composable
internal fun PlaylistScreen(
    model: MuwaModel,
    id: String,
    play: (Track) -> Unit,
    addToPlaylist: (Track) -> Unit,
) {
    val list = model.library.playlists.firstOrNull { it.id == id }
    LazyColumn(Modifier.padding(16.dp)) {
        if (list?.ids.isNullOrEmpty()) item { Text("Добавьте нашиды через меню ⋮") }
        items(model.library.tracks(list?.ids.orEmpty()), key = { it.id }) { t ->
            TrackRow(model, t, play, addToPlaylist)
            TextButton(onClick = { model.library.togglePlaylist(id, t) }) {
                Text("Убрать из плейлиста")
            }
        }
    }
}
