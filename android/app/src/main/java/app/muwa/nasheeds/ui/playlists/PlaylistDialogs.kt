package app.muwa.nasheeds.ui.playlists

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.MuwaModel

/** Inputs and visibility are owned by MuwaApp, including across sheet transitions. */
@Composable
internal fun CreatePlaylistDialog(
    name: String,
    onNameChange: (String) -> Unit,
    onCreate: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Новый плейлист") },
        text = { OutlinedTextField(name, onNameChange, label = { Text("Название") }) },
        confirmButton = { TextButton(onClick = onCreate) { Text("Создать") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PlaylistPickerSheet(
    model: MuwaModel,
    onSelect: (String) -> Unit,
    onCreate: () -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(24.dp)) {
            Text("Добавить в плейлист", style = MaterialTheme.typography.titleLarge)
            model.library.playlists.forEach { p ->
                TextButton(onClick = { onSelect(p.id) }) { Text(p.name) }
            }
            TextButton(onClick = onCreate) { Text("Создать плейлист") }
        }
    }
}
