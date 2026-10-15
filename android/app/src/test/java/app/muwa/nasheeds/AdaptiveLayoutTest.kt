package app.muwa.nasheeds

import app.muwa.nasheeds.ui.design.MuwaAdaptiveLayout
import org.junit.Assert.*
import org.junit.Test

class AdaptiveLayoutTest {
    @Test
    fun phoneLandscapeRetainsPhoneCollectionsAndSingleColumnProfile() {
        val layout = MuwaAdaptiveLayout(874f, 260f, 402)
        assertFalse(layout.wideTablet)
        assertEquals(5, layout.popularPageSize)
        assertEquals(1, layout.popularColumns)
        assertEquals(3, layout.libraryColumns)
        assertEquals(20, layout.homePadding)
        assertEquals(5, layout.screenPadding)
    }

    @Test
    fun tabletUsesTheReferenceGridAndPaddingAtBothWidths() {
        val compact = MuwaAdaptiveLayout(744f, 900f, 744)
        assertTrue(compact.wideTablet)
        assertEquals(3, compact.recommendationColumns)
        assertEquals(1, compact.popularColumns)
        assertEquals(4, compact.libraryColumns)
        assertEquals(28, compact.homePadding)
        val large = MuwaAdaptiveLayout(1100f, 750f, 744)
        assertEquals(2, large.popularColumns)
        assertEquals(4, large.recommendationColumns)
        assertEquals(6, large.popularPageSize)
        assertEquals(40, large.homePadding)
    }

    @Test
    fun narrowPhoneKeepsTwoLibraryColumnsAndCarousel() {
        val layout = MuwaAdaptiveLayout(360f, 400f, 360)
        assertFalse(layout.wideTablet)
        assertEquals(2, layout.libraryColumns)
        assertEquals(5, layout.popularPageSize)
    }
}
