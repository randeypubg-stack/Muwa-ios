package app.muwa.nasheeds.ui.catalog

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.Track
import app.muwa.nasheeds.ui.components.TrackRow

@Composable
internal fun SavedTracksScreen(
    model: MuwaModel,
    route: String,
    play: (Track) -> Unit,
    playlist: (Track) -> Unit,
) {
    val tracks =
        when (route) {
            "favorites" -> model.library.tracks(model.library.favorites)
            "history" -> model.library.tracks(model.library.history)
            "downloads" ->
                model.library.tracks(model.downloads.downloaded).filter {
                    model.downloads.local(it) != null
                }
            else -> model.library.tracks(model.library.queue)
        }
    LazyColumn(Modifier.padding(horizontal = 16.dp)) {
        if (tracks.isEmpty())
            item { Text("Пока пусто", Modifier.padding(30.dp), color = Color.Gray) }
        items(tracks, key = { it.id }) { t ->
            TrackRow(model, t, play, playlist)
            if (route == "downloads")
                TextButton(
                    onClick = {
                        runCatching { model.downloads.remove(t) }
                            .onFailure { model.error = it.message }
                    }
                ) {
                    Icon(Icons.Default.Delete, null)
                    Spacer(Modifier.width(8.dp))
                    Text("Удалить загрузку")
                }
        }
    }
}
