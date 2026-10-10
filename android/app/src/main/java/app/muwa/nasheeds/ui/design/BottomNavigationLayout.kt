package app.muwa.nasheeds.ui.design

/** Shared visual reference: owner-approved Build 50, 18 points on a 874-point window.
 * Use density-independent window height, not physical pixels or screenHeightDp
 * (which can exclude system bars). Android system controls remain unobstructed.
 */
object BottomNavigationLayout {
    const val playerGapDp = 8f
    private const val referenceHeightDp = 874f
    private const val referenceClearanceDp = 18f

    fun bottomClearanceDp(windowHeightDp: Float, systemBottomDp: Float): Float {
        val height = if (windowHeightDp.isFinite() && windowHeightDp > 0f)
            windowHeightDp else referenceHeightDp
        val inset = if (systemBottomDp.isFinite()) systemBottomDp.coerceAtLeast(0f) else 0f
        val proportional = (height * referenceClearanceDp / referenceHeightDp).coerceIn(12f, 28f)
        return maxOf(proportional, inset)
    }
}
