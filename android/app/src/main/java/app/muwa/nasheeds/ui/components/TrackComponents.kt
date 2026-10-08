package app.muwa.nasheeds.ui.components

import android.content.Intent
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.R
import coil.compose.AsyncImage

@Composable
fun Cover(track: Track, modifier: Modifier) {
    AsyncImage(
        track.artwork,
        contentDescription = "Обложка ${track.title}",
        modifier = modifier.clip(RoundedCornerShape(20.dp)),
        placeholder = painterResource(R.drawable.app_mark),
        error = painterResource(R.drawable.app_mark),
        contentScale = androidx.compose.ui.layout.ContentScale.Crop,
    )
}

@Composable
fun ActionCard(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    action: () -> Unit,
) {
    Card(onClick = action, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null)
            Text(title, Modifier.weight(1f).padding(start = 16.dp))
            Icon(Icons.AutoMirrored.Filled.ArrowForward, null)
        }
    }
}

@Composable
fun TrackRow(model: MuwaModel, track: Track, play: (Track) -> Unit, playlist: (Track) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val context = LocalContext.current
    Row(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).clickable { play(track) }.padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Cover(track, Modifier.size(52.dp))
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(track.title, maxLines = 1)
                Text(track.artist, fontSize = 12.sp, color = Color.Gray, maxLines = 1)
            }
            Text(
                if (model.track?.id == track.id && model.playing) "▥"
                else formatTime(track.duration * 1000),
                fontSize = 11.sp,
                color = Color.Gray,
            )
        }
        Box {
            IconButton(onClick = { menu = true }) {
                Icon(Icons.Default.MoreVert, "Действия ${track.title}")
            }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem(
                    text = {
                        Text(
                            if (track.id in model.library.favorites) "Убрать из избранного"
                            else "В избранное"
                        )
                    },
                    onClick = {
                        model.library.like(track)
                        menu = false
                    },
                )
                DropdownMenuItem(
                    text = { Text("Добавить в плейлист") },
                    onClick = {
                        playlist(track)
                        menu = false
                    },
                )
                DropdownMenuItem(
                    text = { Text("Играть следующим") },
                    onClick = {
                        model.addQueue(track, true)
                        menu = false
                    },
                )
                DropdownMenuItem(
                    text = { Text("Добавить в очередь") },
                    onClick = {
                        model.addQueue(track)
                        menu = false
                    },
                )
                DropdownMenuItem(
                    text = {
                        Text(
                            if (track.id in model.downloads.downloaded) "Удалить загрузку"
                            else if (model.downloads.progress.containsKey(track.id))
                                "Отменить скачивание"
                            else "Скачать MP3"
                        )
                    },
                    leadingIcon = {
                        Icon(
                            if (track.id in model.downloads.downloaded) Icons.Default.Delete
                            else Icons.Default.Download,
                            null,
                        )
                    },
                    onClick = {
                        menu = false
                        runCatching {
                                if (track.id in model.downloads.downloaded)
                                    model.downloads.remove(track)
                                else if (model.downloads.progress.containsKey(track.id))
                                    model.downloads.cancel(track)
                                else model.downloads.download(track) { model.error = it.message }
                            }
                            .onFailure { model.error = it.message }
                    },
                )
                DropdownMenuItem(
                    text = { Text("Поделиться") },
                    onClick = {
                        menu = false
                        context.startActivity(
                            Intent.createChooser(
                                Intent(Intent.ACTION_SEND)
                                    .setType("text/plain")
                                    .putExtra(Intent.EXTRA_TEXT, "${track.title}\n${track.audio}"),
                                "Поделиться нашидом",
                            )
                        )
                    },
                )
            }
        }
    }
    model.downloads.progress[track.id]?.let {
        LinearProgressIndicator(progress = { it }, modifier = Modifier.fillMaxWidth())
    }
}
