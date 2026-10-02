package app.muwa.nasheeds.ui.search

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.components.TrackRow

@Composable
fun SearchScreen(model: MuwaModel, play: (Track) -> Unit, playlist: (Track) -> Unit) {
    var query by rememberSaveableState("")
    var recent by rememberSaveableState(false)
    val rows = if (recent) model.library.tracks(model.library.history) else model.library.catalog
    val results =
        rows.filter {
            it.title.contains(query.trim(), true) || it.artist.contains(query.trim(), true)
        }
    Column(Modifier.padding(16.dp)) {
        OutlinedTextField(
            query,
            { query = it },
            label = { Text("Название или автор") },
            modifier = Modifier.fillMaxWidth(),
        )
        Row { FilterChip(recent, { recent = !recent }, label = { Text("Недавние") }) }
        LazyColumn {
            if (results.isEmpty()) item { Text("Ничего не найдено", Modifier.padding(24.dp)) }
            items(results, key = { it.id }) { TrackRow(model, it, play, playlist) }
        }
    }
}
