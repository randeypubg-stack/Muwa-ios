package app.muwa.nasheeds.ui.catalog

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.Track
import app.muwa.nasheeds.ui.components.TrackRow

@Composable
internal fun CollectionScreen(
    model: MuwaModel,
    collection: String,
    play: (Track, List<Track>) -> Unit,
    playlist: (Track) -> Unit,
) {
    val tracks =
        when (collection) {
            "short" -> model.library.catalog.filter { it.duration <= 180 }
            "long" -> model.library.catalog.filter { it.duration > 180 }
            else -> model.library.catalog
        }
    LazyColumn(
        Modifier.padding(horizontal = 20.dp),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        items(tracks, key = { it.id }) { TrackRow(model, it, { t -> play(t, tracks) }, playlist) }
    }
}
