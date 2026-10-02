package app.muwa.nasheeds

import android.content.Intent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class NavigationAndQueueTest {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun collectionNavigationReturnsToHome() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        ActivityScenario.launch<MainActivity>(
                Intent(context, MainActivity::class.java).putExtra("review.route", "home")
            )
            .use {
                compose.onNodeWithTag("home.screen").assertExists()
                compose.onNodeWithText("Все").performClick()
                compose.onNodeWithText("Вся коллекция").assertExists()
                UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
                compose.onNodeWithTag("home.screen").assertExists()
            }
    }

    @Test
    fun queueControlsReorderAndRemovePersistedItems() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        // Other screen fixtures can leave a paused Media3 session. Use the real
        // shared library and start this interaction check with an empty player.
        context.stopService(Intent(context, PlaybackService::class.java))
        instrumentation.waitForIdleSync()
        val library = AppGraph.library
        val saved = library.queue
        val tracks = library.catalog.take(3)
        val ids = tracks.map { it.id }
        instrumentation.runOnMainSync { library.replaceQueue(ids) }
        try {
            ActivityScenario.launch<MainActivity>(
                    Intent(context, MainActivity::class.java).putExtra("review.route", "queue")
                )
                .use {
                    compose.onNodeWithTag("queue.screen").assertExists()
                    compose
                        .onNodeWithContentDescription("Порядок ${tracks[0].title}")
                        .performClick()
                    compose.onNodeWithText("Переместить ниже").performClick()
                    compose.waitForIdle()
                    assertEquals(listOf(ids[1], ids[0], ids[2]), Library(context).queue)
                    compose.onNodeWithTag("queue.remove.${ids[0]}").performClick()
                    compose.waitForIdle()
                    assertEquals(listOf(ids[1], ids[2]), Library(context).queue)
                }
        } finally {
            instrumentation.runOnMainSync { library.replaceQueue(saved) }
        }
    }
}
