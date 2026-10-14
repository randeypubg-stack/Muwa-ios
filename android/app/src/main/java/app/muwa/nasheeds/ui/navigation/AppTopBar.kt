package app.muwa.nasheeds.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import app.muwa.nasheeds.MuwaModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AppTopBar(route: String, model: MuwaModel, onSearch: () -> Unit) {
    TopAppBar(
        title = {
            Text(
                when {
                    route.startsWith("collection:") ->
                        when (route.substringAfter(':')) {
                            "short" -> "На несколько минут"
                            "long" -> "Слушать подольше"
                            else -> "Вся коллекция"
                        }
                    route.startsWith("playlist:") ->
                        model.library.playlists
                            .firstOrNull { it.id == route.substringAfter(':') }
                            ?.name ?: "Плейлист"
                    else ->
                        mapOf(
                            "home" to "Главная",
                            "library" to "Библиотека",
                            "profile" to "Профиль",
                            "search" to "Поиск",
                            "queue" to "Очередь",
                            "downloads" to "Загрузки",
                            "favorites" to "Избранное",
                            "history" to "Недавние",
                            "premium" to "Muwa Premium",
                            "promo" to "Промокод",
                            "settings" to "Настройки",
                            "auth" to "Аккаунт",
                            "subtitles" to "Субтитры",
                            "publication" to "Публикация",
                        )[route] ?: "Muwa"
                }
            )
        },
        actions = { IconButton(onClick = onSearch) { Icon(Icons.Default.Search, "Поиск") } },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
    )
}
