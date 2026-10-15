package app.muwa.nasheeds.ui.catalog

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.Track
import app.muwa.nasheeds.ui.components.EmptyState
import app.muwa.nasheeds.ui.components.TrackRow
import app.muwa.nasheeds.ui.design.*

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
    LazyColumn(
        Modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val title =
            when (route) {
                "favorites" -> "Избранные"
                "history" -> "Недавно прослушано"
                else -> "Загрузки"
            }
        val subtitle =
            when (route) {
                "favorites" -> "Сохранённые любимые нашиды"
                "history" -> "Последние прослушивания"
                else -> "Нашиды, сохранённые для офлайн-прослушивания"
            }
        item {
            Text(title, style = MaterialTheme.typography.headlineLarge)
            Text(subtitle, color = MuwaColors.Secondary)
        }
        if (tracks.isEmpty())
            item {
                EmptyState(
                    when (route) {
                        "favorites" -> Icons.Default.FavoriteBorder
                        "history" -> Icons.Default.History
                        else -> Icons.Default.DownloadForOffline
                    },
                    when (route) {
                        "favorites" -> "Избранное пусто"
                        "history" -> "История пока пустая"
                        else -> "Загрузок пока нет"
                    },
                    when (route) {
                        "favorites" -> "Добавляйте нашиды в избранное из меню большого плеера."
                        "history" -> "Прослушанные нашиды будут появляться здесь автоматически."
                        else -> "Сохраните нашид из меню плеера, чтобы слушать без интернета."
                    },
                )
            }
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
