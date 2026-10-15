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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.design.*
import coil.compose.AsyncImage

@Composable
fun Cover(
    track: Track,
    modifier: Modifier,
    radius: Dp = 20.dp,
    contentScale: androidx.compose.ui.layout.ContentScale =
        androidx.compose.ui.layout.ContentScale.Fit,
) {
    var placeholder by remember(track.artwork) { mutableStateOf(true) }
    val shape = RoundedCornerShape(radius)
    Box(
        modifier
            .clip(shape)
            .background(Color.White.copy(alpha = .045f))
            .border(1.dp, Color.White.copy(alpha = .065f), shape),
        contentAlignment = Alignment.Center,
    ) {
        AsyncImage(
            track.artwork,
            contentDescription = "Обложка ${track.title}",
            modifier = Modifier.fillMaxSize(),
            contentScale = contentScale,
            onState = { placeholder = it !is coil.compose.AsyncImagePainter.State.Success },
        )
        if (placeholder)
            Icon(
                Icons.Default.MusicNote,
                null,
                Modifier.fillMaxSize(.25f).sizeIn(maxWidth = 30.dp, maxHeight = 30.dp),
                tint = Color.White.copy(alpha = .72f),
            )
    }
}

@Composable
fun TrackRow(model: MuwaModel, track: Track, play: (Track) -> Unit, playlist: (Track) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val context = LocalContext.current
    Row(
        Modifier.fillMaxWidth().padding(vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).clickable { play(track) },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Cover(track, Modifier.size(44.dp), 13.dp)
            Column(Modifier.weight(1f).padding(horizontal = 11.dp)) {
                Text(
                    track.title,
                    fontSize = 14.sp,
                    lineHeight = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    "${track.artist}  •  ${formatTime(track.duration * 1000)}",
                    fontSize = 10.sp,
                    lineHeight = 14.sp,
                    color = MuwaColors.Secondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (model.track?.id == track.id && model.playing)
                Icon(
                    Icons.Default.GraphicEq,
                    "Сейчас играет",
                    Modifier.size(20.dp),
                    tint = Color(0xFFE4CA63),
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
