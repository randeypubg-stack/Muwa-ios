package app.muwa.nasheeds

import android.content.Intent
import android.content.pm.ActivityInfo
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.ViewModelProvider
import androidx.media3.common.Player
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class NavigationAndQueueTest {
    @Before
    fun loadReviewCatalog() {
        installReviewCatalog()
    }

    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun navigationKeepsApprovedWindowAnchorAcrossTabsAndRotation() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        ActivityScenario.launch<MainActivity>(
            Intent(context, MainActivity::class.java).putExtra("review.route", "home")
        ).use { scenario ->
            for (orientation in listOf(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,
                ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, ActivityInfo.SCREEN_ORIENTATION_PORTRAIT)) {
                scenario.onActivity { it.requestedOrientation = orientation }
                compose.waitUntil(timeoutMillis = 20_000) {
                    var settled = false
                    scenario.onActivity {
                        val view = it.window.decorView
                        settled = view.width > 0 && view.height > 0 &&
                            (view.width > view.height) == (orientation == ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE)
                    }
                    settled
                }
                for (tab in listOf("home", "library", "profile")) {
                    compose.onNodeWithTag("tab.$tab").assertIsDisplayed().performClick()
                    assertBottomAnchor(scenario)
                }
                scenario.onActivity { ViewModelProvider(it)[MuwaModel::class.java]
                    .play(AppGraph.library.catalog.first(), autoplay = false) }
                compose.waitUntil(timeoutMillis = 20_000) {
                    compose.onAllNodesWithTag("mini-player").fetchSemanticsNodes().isNotEmpty()
                }
                assertBottomAnchor(scenario)
                compose.onNodeWithTag("mini-player").assertIsDisplayed()
            }
        }
    }

    private fun assertBottomAnchor(scenario: ActivityScenario<MainActivity>) {
        compose.waitForIdle()
        val bar = compose.onNodeWithTag("bottom-navigation").assertIsDisplayed()
            .getUnclippedBoundsInRoot()
        scenario.onActivity { activity ->
            val view = activity.window.decorView
            val density = activity.resources.displayMetrics.density
            val height = view.height / density
            val insets = ViewCompat.getRootWindowInsets(view)!!.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            // Independent visual reference; changing production constants must fail this check.
            val expected = maxOf((height * 18f / 874f).coerceIn(12f, 28f), insets.bottom / density)
            assertEquals("Navigation changed its approved physical-window anchor",
                expected, height - bar.bottom.value, 1f)
            assertTrue("Navigation controls overlap Android system navigation",
                bar.bottom.value <= (view.height - insets.bottom) / density + 1f)
            assertTrue("Navigation exceeds the left safe edge", bar.left.value >= insets.left / density)
            assertTrue("Navigation exceeds the right safe edge",
                bar.right.value <= (view.width - insets.right) / density)
        }
    }

    @Test
    fun reducedMotionSubtitlesFollowSeekAndKeepTheWholeArabicPhrase() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        context.stopService(Intent(context, PlaybackService::class.java))
        instrumentation.waitForIdleSync()
        val device = UiDevice.getInstance(instrumentation)
        val originalScale = device.executeShellCommand("settings get global animator_duration_scale").trim()
        val track = AppGraph.library.catalog.first()
        val file = File(context.cacheDir, if (track.captionsRevision > 0)
            "subtitles-${track.id}-r${track.captionsRevision}.json" else "subtitles-${track.id}.json")
        val previous = file.takeIf { it.exists() }?.readBytes()
        val phrase = "نور في القلب وسلام في الروح ورحمة الله والأمل في كل يوم وليلة"
        file.writeText("""{"segments":[{"start":0,"end":5,"ar":"السلام عليكم"},
            {"start":5,"end":10,"ar":"$phrase"},{"start":10,"end":15,"ar":"رحمة وسكينة"}]}""")
        try {
            device.executeShellCommand("settings put global animator_duration_scale 0")
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
                .putExtra("review.route", "player")).use { scenario ->
                compose.waitUntil(timeoutMillis = 20_000) {
                    var ready = false
                    scenario.onActivity { ready = ViewModelProvider(it)[MuwaModel::class.java]
                        .controller?.playbackState == Player.STATE_READY }
                    ready
                }
                compose.onNodeWithTag("player.subtitles").performClick()
                compose.waitUntil(timeoutMillis = 15_000) {
                    compose.onAllNodes(hasTestTag("subtitle.line.0") and isSelected())
                        .fetchSemanticsNodes().size == 1
                }
                scenario.onActivity {
                    val model = ViewModelProvider(it)[MuwaModel::class.java]
                    model.seek(6_000); model.seek(11_000)
                }
                compose.waitUntil(timeoutMillis = 10_000) {
                    compose.onAllNodes(hasTestTag("subtitle.line.2") and isSelected())
                        .fetchSemanticsNodes().size == 1
                }
                compose.onNodeWithTag("subtitles.list").performScrollToIndex(1)
                compose.onNodeWithText(phrase, useUnmergedTree = true).assertExists()
                compose.onNodeWithTag("subtitle.line.1").performClick()
                compose.onNodeWithTag("subtitles.follow").assertIsOff()
                compose.waitUntil(timeoutMillis = 10_000) {
                    compose.onAllNodes(hasTestTag("subtitle.line.1") and isSelected())
                        .fetchSemanticsNodes().size == 1
                }
                assertBottomAnchor(scenario)
                val shots = File(context.getExternalFilesDir(null), "screenshots").apply { mkdirs() }
                assertTrue(device.takeScreenshot(File(shots, "subtitle-reader-reduced-motion-portrait.png")))
                scenario.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
                compose.waitUntil(timeoutMillis = 20_000) {
                    var rotated = false
                    scenario.onActivity { rotated = it.window.decorView.width > it.window.decorView.height }
                    rotated
                }
                val list = compose.onNodeWithTag("subtitles.list").assertIsDisplayed()
                val bounds = list.getUnclippedBoundsInRoot()
                assertTrue("Landscape header left no readable subtitle viewport",
                    (bounds.bottom - bounds.top).value >= 40f)
                list.performScrollToIndex(1)
                compose.onNodeWithText(phrase, useUnmergedTree = true).assertIsDisplayed()
                compose.onNodeWithTag("subtitles.follow").assertIsOff()
                assertBottomAnchor(scenario)
                assertTrue(device.takeScreenshot(File(shots, "subtitle-reader-reduced-motion-landscape.png")))
            }
        } finally {
            if (previous == null) file.delete() else file.writeBytes(previous)
            if (originalScale == "null") device.executeShellCommand("settings delete global animator_duration_scale")
            else device.executeShellCommand("settings put global animator_duration_scale $originalScale")
        }
    }

    @Test
    fun popularPagesBrowseTheWholeCatalogInBothDirections() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        ActivityScenario.launch<MainActivity>(
                Intent(context, MainActivity::class.java).putExtra("review.route", "home")
            )
            .use {
                val pages = compose.onNodeWithTag("popular.pages")
                compose.onNodeWithTag("home.screen").performScrollToNode(hasTestTag("popular.pages"))
                compose.onNodeWithTag("popular.page.muwa-01").assertIsDisplayed()
                pages.performTouchInput { swipeLeft() }
                compose.onNodeWithTag("popular.page.muwa-06").assertIsDisplayed()
                pages.performTouchInput { swipeRight() }
                compose.onNodeWithTag("popular.page.muwa-01").assertIsDisplayed()
            }
    }

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
                // UIAutomator returns after injecting Back, before Compose
                // necessarily commits the destination on a busy emulator.
                compose.waitUntil(timeoutMillis = 10_000) {
                    compose.onAllNodesWithTag("home.screen").fetchSemanticsNodes().size == 1
                }
                compose.onNodeWithTag("home.screen").assertExists()
            }
    }

    @Test
    fun playerActionsStayInsideSafeAreaAndNavigateInBothOrientations() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        context.stopService(Intent(context, PlaybackService::class.java))
        instrumentation.waitForIdleSync()
        // Navigate through the real cached/manual reader without requesting
        // recognition or depending on a paid provider during a layout check.
        val track = AppGraph.library.catalog.first()
        val captionFile =
            File(
                context.cacheDir,
                if (track.captionsRevision > 0)
                    "subtitles-${track.id}-r${track.captionsRevision}.json"
                else "subtitles-${track.id}.json",
            )
        val savedCaptions = captionFile.takeIf { it.exists() }?.readBytes()
        captionFile.writeText(
            """{"segments":[{"start":0,"end":5,"ar":"نص محفوظ","ru":"Сохранённый текст"}]}"""
        )
        try {
            ActivityScenario.launch<MainActivity>(
                    Intent(context, MainActivity::class.java).putExtra("review.route", "player")
                )
                .use { scenario ->
                    for (orientation in
                        listOf(
                            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,
                            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
                        )) {
                        scenario.onActivity { it.requestedOrientation = orientation }
                        compose.waitUntil(timeoutMillis = 20_000) {
                            val nodes =
                                compose.onAllNodesWithTag("player.screen").fetchSemanticsNodes()
                            nodes.singleOrNull()?.boundsInRoot?.let {
                                (it.width > it.height) ==
                                    (orientation == ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE)
                            } == true
                        }
                        var ready = false
                        compose.waitUntil(timeoutMillis = 20_000) {
                            scenario.onActivity {
                                val controller =
                                    ViewModelProvider(it)[MuwaModel::class.java].controller
                                ready =
                                    controller?.playbackState == Player.STATE_READY &&
                                        controller.playerError == null &&
                                        !controller.playWhenReady &&
                                        controller.duration in 296_000L..298_000L
                            }
                            ready
                        }
                        scenario.onActivity {
                            assertEquals(
                                "asset:///review-audio.mp3",
                                AppGraph.mediaItem(track).localConfiguration?.uri?.toString(),
                            )
                            val reviewMode = AppGraph.reviewPlaybackEnabled
                            try {
                                AppGraph.reviewPlaybackEnabled = false
                                assertTrue(
                                    "Ordinary debug use must retain the real audio source",
                                    AppGraph.mediaItem(track).localConfiguration?.uri?.scheme !=
                                        "asset",
                                )
                            } finally {
                                AppGraph.reviewPlaybackEnabled = reviewMode
                            }
                        }
                        val viewport =
                            compose.onNodeWithTag("player.screen").getUnclippedBoundsInRoot()
                        val safeContent =
                            compose.onNodeWithTag("player.safe-content").getUnclippedBoundsInRoot()
                        scenario.onActivity { activity ->
                            val view = activity.window.decorView
                            val density = activity.resources.displayMetrics.density
                            val insets =
                                ViewCompat.getRootWindowInsets(view)!!.getInsets(
                                    WindowInsetsCompat.Type.systemBars() or
                                        WindowInsetsCompat.Type.displayCutout()
                                )
                            assertEquals(
                                "Player must cover the Activity from the left edge",
                                0f,
                                viewport.left.value,
                                .5f,
                            )
                            assertEquals(
                                "Player must cover the Activity from the top edge",
                                0f,
                                viewport.top.value,
                                .5f,
                            )
                            assertEquals(
                                "Player must end at the Activity right edge",
                                view.width / density,
                                viewport.right.value,
                                .5f,
                            )
                            assertEquals(
                                "Player must end at the Activity bottom edge",
                                view.height / density,
                                viewport.bottom.value,
                                .5f,
                            )
                            assertTrue(
                                "Player content overlaps a left cutout",
                                safeContent.left.value >= insets.left / density,
                            )
                            assertTrue(
                                "Player content overlaps the status bar",
                                safeContent.top.value >= insets.top / density,
                            )
                            assertTrue(
                                "Player content exceeds the right safe edge",
                                safeContent.right.value <= (view.width - insets.right) / density,
                            )
                            assertTrue(
                                "Player content overlaps the navigation bar",
                                safeContent.bottom.value <= (view.height - insets.bottom) / density,
                            )
                        }
                        for (tag in
                            listOf(
                                "player.close",
                                "player.toggle",
                                "player.subtitles",
                                "player.queue",
                            )) {
                            val action =
                                compose
                                    .onNodeWithTag(tag)
                                    .assertIsDisplayed()
                                    .assertHasClickAction()
                            // Unclipped bounds reject a partially visible button, which
                            // assertIsDisplayed alone would accept at the gesture bar.
                            val bounds = action.getUnclippedBoundsInRoot()
                            assertTrue(
                                "$tag is clipped on the left",
                                bounds.left >= safeContent.left,
                            )
                            assertTrue(
                                "$tag is clipped on the right",
                                bounds.right <= safeContent.right,
                            )
                            assertTrue("$tag is clipped at the top", bounds.top >= safeContent.top)
                            assertTrue(
                                "$tag is clipped at the bottom",
                                bounds.bottom <= safeContent.bottom,
                            )
                        }
                        compose.onNodeWithTag("home.screen").assertDoesNotExist()
                        compose.onNodeWithTag("player.queue").performClick()
                        compose.onNodeWithTag("queue.screen").assertIsDisplayed()
                        compose.onNodeWithTag("player.screen").assertDoesNotExist()
                        compose.onNodeWithTag("mini-player").performClick()
                        compose.onNodeWithTag("player.subtitles").performClick()
                        compose.onNodeWithText("Субтитры").assertIsDisplayed()
                        compose.waitUntil(timeoutMillis = 10_000) {
                            compose
                                .onAllNodesWithText("نص محفوظ", useUnmergedTree = true)
                                .fetchSemanticsNodes()
                                .isNotEmpty()
                        }
                        compose.onNodeWithTag("player.screen").assertDoesNotExist()
                        compose.onNodeWithTag("mini-player").performClick()
                        compose.onNodeWithTag("player.close").performClick()
                        compose.onNodeWithText("Субтитры").assertIsDisplayed()
                        compose.onNodeWithTag("mini-player").performClick()
                    }
                }
        } finally {
            if (savedCaptions == null) captionFile.delete()
            else captionFile.writeBytes(savedCaptions)
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
