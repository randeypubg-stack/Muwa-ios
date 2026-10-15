package app.muwa.nasheeds

import app.muwa.nasheeds.ui.design.BottomNavigationLayout
import org.junit.Assert.assertEquals
import org.junit.Test

class BottomNavigationLayoutTest {
    @Test fun approvedPositionAndWindowRatiosRemainStable() {
        val golden = listOf(
            Triple(874f, 0f, 18f), Triple(956f, 0f, 19.688787f),
            Triple(568f, 0f, 12f), Triple(667f, 0f, 13.736842f),
            Triple(402f, 0f, 12f), Triple(1133f, 0f, 23.334096f),
            Triple(1376f, 0f, 28f), Triple(400f, 0f, 12f),
            Triple(874f, 24f, 24f), Triple(874f, 48f, 48f),
            Triple(0f, 0f, 18f), Triple(Float.NaN, 24f, 24f)
        )
        golden.forEach { (height, inset, expected) ->
            assertEquals("Window $height, system inset $inset",
                expected, BottomNavigationLayout.bottomClearanceDp(height, inset), .001f)
        }
        assertEquals(8f, BottomNavigationLayout.playerGapDp, 0f)
    }
}
