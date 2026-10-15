package app.muwa.nasheeds

import app.muwa.nasheeds.ui.navigation.MuwaNavigation
import org.junit.Assert.*
import org.junit.Test

class NavigationHistoryTest {
    @Test
    fun searchReturnsToEveryOriginTab() {
        for (tab in listOf("home", "library", "profile")) {
            val nav = MuwaNavigation(listOf(tab))
            nav.open("search")
            assertEquals(tab, nav.selectedTab)
            nav.back()
            assertEquals(tab, nav.current)
        }
    }

    @Test
    fun playlistDetailReturnsToThePlaylistCollection() {
        val nav = MuwaNavigation(listOf("library"))
        nav.open("playlists")
        nav.open("playlist:owned-id")
        nav.back()
        assertEquals("playlists", nav.current)
        nav.back()
        assertEquals("library", nav.current)
    }

    @Test
    fun nestedPremiumLoginReturnsThroughItsOriginalScreens() {
        val nav = MuwaNavigation(listOf("profile"))
        nav.open("premium")
        nav.open("promo")
        nav.open("auth")
        for (expected in listOf("promo", "premium", "profile")) {
            nav.back()
            assertEquals(expected, nav.current)
        }
    }

    @Test
    fun changingTabsResetsDetailHistoryAndReselectionDoesNotDuplicateRoutes() {
        val nav = MuwaNavigation(listOf("home"))
        nav.open("collection:short")
        nav.selectTab("library")
        nav.open("search")
        nav.open("search")
        nav.back()
        assertEquals(listOf("library"), nav.history)
        nav.back()
        assertEquals("library", nav.current)
    }

    @Test
    fun directDetailEntryHasAUsableParent() {
        for ((detail, parent) in
            listOf(
                "playlist:owned-id" to "playlists",
                "collection:short" to "home",
                "auth" to "profile",
                "downloads" to "library",
            )) {
            val nav = MuwaNavigation(listOf(detail))
            nav.back()
            assertEquals(parent, nav.current)
        }
    }
}
