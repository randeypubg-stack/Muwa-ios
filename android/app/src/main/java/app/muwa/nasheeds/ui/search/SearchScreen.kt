package app.muwa.nasheeds.ui.search

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.components.TrackRow
import app.muwa.nasheeds.ui.state.rememberSaveableState

@Composable
fun SearchScreen(model: MuwaModel, play: (Track, List<Track>) -> Unit, playlist: (Track) -> Unit) {
    var query by rememberSaveableState("")
    var filter by rememberSaveableState("Все")
    val rows =
        when (filter) {
            "Недавние" -> model.library.tracks(model.library.history)
            "Арабские" ->
                model.library.catalog.filter { it.title.any { char -> char in '\u0600'..'\u06FF' } }
            else -> model.library.catalog
        }
    val results =
        rows.filter {
            it.title.contains(query.trim(), true) || it.artist.contains(query.trim(), true)
        }
    Column(
        Modifier.fillMaxSize().testTag("search.screen").padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        TextField(
            query,
            { query = it },
            placeholder = { Text("Название или автор") },
            singleLine = true,
            leadingIcon = { Icon(Icons.Default.Search, null) },
            trailingIcon = {
                if (query.isNotEmpty())
                    IconButton(onClick = { query = "" }) {
                        Icon(Icons.Default.Cancel, "Очистить поиск")
                    }
            },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(19.dp),
            colors =
                TextFieldDefaults.colors(
                    focusedContainerColor = Color.White.copy(alpha = .055f),
                    unfocusedContainerColor = Color.White.copy(alpha = .055f),
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
        )
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            listOf("Все", "Нашиды", "Арабские", "Недавние").forEach { item ->
                Box(
                    Modifier.background(
                            Color.White.copy(alpha = if (filter == item) .14f else .05f),
                            CircleShape,
                        )
                        .clickable { filter = item }
                        .padding(horizontal = 13.dp, vertical = 10.dp)
                ) {
                    Text(
                        item,
                        fontSize = 11.sp,
                        lineHeight = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
        LazyColumn {
            if (results.isEmpty())
                item {
                    app.muwa.nasheeds.ui.components.EmptyState(
                        Icons.Default.Search,
                        "Ничего не найдено",
                        "Попробуйте другое название или имя автора.",
                    )
                }
            items(results, key = { it.id }) {
                TrackRow(model, it, { track -> play(track, results) }, playlist)
                HorizontalDivider(color = Color.White.copy(alpha = .05f))
            }
        }
    }
}
