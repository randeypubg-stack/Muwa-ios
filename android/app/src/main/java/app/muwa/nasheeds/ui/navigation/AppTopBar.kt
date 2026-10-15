package app.muwa.nasheeds.ui.navigation

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.ui.design.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AppTopBar(
    route: String,
    model: MuwaModel,
    scroll: TopAppBarScrollBehavior,
    onSearch: () -> Unit,
    onBack: () -> Unit,
    onReaderClose: () -> Unit,
) {
    val main = route in listOf("home", "library", "profile")
    val title =
        when {
            route.startsWith("collection:") ->
                when (route.substringAfter(':')) {
                    "short" -> "На несколько минут"
                    "long" -> "Слушать подольше"
                    else -> "Вся коллекция"
                }
            route.startsWith("playlist:") ->
                model.library.playlists.firstOrNull { it.id == route.substringAfter(':') }?.name
                    ?: "Плей-лист"
            else ->
                mapOf(
                    "home" to "Главная",
                    "library" to "Библиотека",
                    "profile" to "Профиль",
                    "search" to "Поиск",
                    "queue" to "Очередь",
                    "downloads" to "Загрузки",
                    "favorites" to "Избранные",
                    "history" to "Недавно прослушано",
                    "playlists" to "Мои плей-листы",
                    "publications" to "Мои публикации",
                    "drafts" to "Черновики публикаций",
                    "premium" to "Muwa Premium",
                    "promo" to "Промокод",
                    "settings" to "Настройки",
                    "auth" to "Аккаунт",
                    "subtitles" to "Текст нашида",
                    "publication" to "Публикация",
                )[route] ?: "Muwa"
        }
    val search: @Composable RowScope.() -> Unit = {
        if (route == "subtitles") TextButton(onClick = onReaderClose) { Text("Готово") }
        else if (main)
            IconButton(
                onClick = onSearch,
                modifier = Modifier.padding(end = 16.dp).size(44.dp).glassPanel(16.dp),
            ) {
                Icon(Icons.Default.Search, "Поиск", Modifier.size(24.dp))
            }
    }
    if (route == "home")
        LargeTopAppBar(
            title = { Text(title, fontWeight = FontWeight.Bold) },
            actions = search,
            scrollBehavior = scroll,
            colors =
                TopAppBarDefaults.largeTopAppBarColors(
                    containerColor = Color.Transparent,
                    scrolledContainerColor = MuwaColors.Background.copy(alpha = .96f),
                ),
        )
    else if (main)
        Column(
            Modifier.windowInsetsPadding(WindowInsets.statusBars)
                .padding(start = 20.dp, end = 4.dp, top = 10.dp, bottom = 10.dp)
        ) {
            Row {
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.headlineLarge)
                    Text(
                        if (route == "library") "Сохранённое и ваши публикации"
                        else if (model.user == null) "Гостевой режим" else "Аккаунт и настройки",
                        style = MaterialTheme.typography.bodySmall,
                        color = MuwaColors.Secondary,
                    )
                }
                search()
            }
        }
    else
        TopAppBar(
            title = { Text(title, style = MaterialTheme.typography.titleMedium) },
            actions = search,
            navigationIcon = {
                if (route != "subtitles")
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад")
                    }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
        )
}
