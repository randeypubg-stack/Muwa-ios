package app.muwa.nasheeds

import android.content.Intent
import androidx.compose.ui.test.*
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import java.io.File
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class NativeScreensTest {
    @get:org.junit.Rule val compose = androidx.compose.ui.test.junit4.createEmptyComposeRule()

    @Before
    fun loadReviewCatalog() {
        installReviewCatalog()
    }

    @Test
    fun captureNativeScreens() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val device = UiDevice.getInstance(instrumentation)
        device.wakeUp()
        device.executeShellCommand("wm dismiss-keyguard")
        device.pressHome()
        val output = File("/sdcard/Download/muwa-screen-review")
        device.executeShellCommand("mkdir -p ${output.path}")
        assertFalse(FeatureAccess.premiumRestrictionsEnabled)
        for (route in
            listOf(
                "home",
                "library",
                "profile",
                "premium",
                "promo",
                "settings",
                "search",
                "queue",
                "downloads",
                "favorites",
                "history",
                "playlists",
                "drafts",
                "publications",
                "auth",
                "publication",
                "player",
            )) {
            ActivityScenario.launch<MainActivity>(
                    Intent(context, MainActivity::class.java).putExtra("review.route", route)
                )
                .use {
                    assertTrue(
                        "Muwa did not launch for $route",
                        device.wait(Until.hasObject(By.pkg(context.packageName)), 20000),
                    )
                    device.waitForIdle()
                    Thread.sleep(if (route == "player") 4000 else 1500)
                    assertTrue(
                        "Screenshot failed: $route",
                        device.takeScreenshot(File(output, "$route.png")),
                    )
                }
        }
        assertTrue(File(output, "player.png").length() > 0)
    }

    @Test
    fun registrationRequiresMatchingConfirmationWithoutCreatingAnAccount() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        ActivityScenario.launch<MainActivity>(
                Intent(context, MainActivity::class.java).putExtra("review.route", "auth")
            )
            .use {
                compose.onNodeWithTag("auth.register-switch").performClick()
                compose.onNodeWithTag("auth.name").performTextInput("Проверка")
                compose.onNodeWithTag("auth.email").performTextInput("review@example.invalid")
                compose
                    .onNodeWithTag("auth.password")
                    .performScrollTo()
                    .performTextInput("test-password")
                compose
                    .onNodeWithTag("auth.confirmation")
                    .performScrollTo()
                    .performTextInput("different-password")
                compose.onNodeWithTag("auth.submit").assertIsNotEnabled()
                compose.onNodeWithTag("auth.confirmation").performTextClearance()
                compose.onNodeWithTag("auth.confirmation").performTextInput("test-password")
                compose.onNodeWithTag("auth.submit").assertIsEnabled()
            }
    }

    @Test
    fun libraryPersistenceAndEmptyQueue() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val library = Library(context)
        val id = library.createPlaylist("Проверка сохранения")
        val track = library.catalog.first()
        library.togglePlaylist(id, track)
        assertEquals(listOf(track.id), Library(context).playlists.first { it.id == id }.ids)
        library.replaceQueue(emptyList())
        assertTrue(Library(context).queue.isEmpty())
        library.replaceQueue(library.catalog.map { it.id })
        library.deletePlaylist(id)
        assertFalse(Library(context).playlists.any { it.id == id })
    }
}
