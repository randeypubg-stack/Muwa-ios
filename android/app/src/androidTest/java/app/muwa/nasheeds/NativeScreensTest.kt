package app.muwa.nasheeds

import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Test
import org.junit.Assert.*
import java.io.File

class NativeScreensTest {
    @Test fun captureNativeScreens() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val context=instrumentation.targetContext
        val device=UiDevice.getInstance(instrumentation)
        val output=File(context.getExternalFilesDir(null),"screenshots").apply {mkdirs()}
        assertFalse(FeatureAccess.premiumRestrictionsEnabled)
        for(route in listOf("home","library","profile","premium","promo","settings","search","queue","downloads","auth","publication","player")) {
            ActivityScenario.launch<MainActivity>(Intent(context,MainActivity::class.java).putExtra("review.route",route)).use {
                assertTrue("Muwa did not launch for $route",device.wait(Until.hasObject(By.pkg(context.packageName)),20000))
                device.waitForIdle();Thread.sleep(if(route=="player") 4000 else 1500)
                assertTrue("Screenshot failed: $route",device.takeScreenshot(File(output,"$route.png")))
            }
        }
        assertTrue(File(output,"player.png").length()>0)
    }
    @Test fun libraryPersistenceAndEmptyQueue() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val library=Library(context)
        val id=library.createPlaylist("Проверка сохранения")
        val track=library.catalog.first()
        library.togglePlaylist(id,track)
        assertEquals(listOf(track.id),Library(context).playlists.first {it.id==id}.ids)
        library.replaceQueue(emptyList())
        assertTrue(Library(context).queue.isEmpty())
        library.replaceQueue(library.catalog.map {it.id})
        library.deletePlaylist(id)
        assertFalse(Library(context).playlists.any {it.id==id})
    }
}
