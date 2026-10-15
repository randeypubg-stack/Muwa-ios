package app.muwa.nasheeds.ui.navigation

import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.listSaver

/** The app's single route owner. Detail screens return to their actual origin. */
internal class MuwaNavigation(initial: List<String>) {
    var history by mutableStateOf(initial.ifEmpty { listOf("home") }.toList())
        private set

    val current: String
        get() = history.last()

    val selectedTab: String
        get() = rootFor(history.first())

    fun open(destination: String) {
        if (destination != current) history = history + destination
    }

    fun selectTab(tab: String) {
        require(tab in listOf("home", "library", "profile"))
        history = listOf(tab)
    }

    fun back() {
        history = if (history.size > 1) history.dropLast(1) else listOf(parentFor(current))
    }

    private fun rootFor(route: String): String =
        when {
            route in listOf("home", "search") || route.startsWith("collection:") -> "home"
            route in listOf("profile", "premium", "promo", "settings", "auth") -> "profile"
            else -> "library"
        }

    private fun parentFor(route: String): String =
        when {
            route in listOf("home", "library", "profile") -> route
            route.startsWith("playlist:") -> "playlists"
            route.startsWith("collection:") || route in listOf("search", "subtitles") -> "home"
            else -> rootFor(route)
        }

    companion object {
        val Saver =
            listSaver<MuwaNavigation, String>(
                save = { it.history },
                restore = { MuwaNavigation(it) },
            )
    }
}
