package app.muwa.nasheeds.ui.design

/**
 * iOS reference rules, using the current content window and device form factor. Does not own system
 * insets or the navigation anchor. A wide phone stays a phone.
 */
internal data class MuwaAdaptiveLayout(
    val width: Float,
    val height: Float,
    val smallestWidth: Int,
) {
    val tablet
        get() = smallestWidth >= 600

    val wideTablet
        get() = tablet && width >= 700

    val landscape
        get() = width > height

    val screenPadding
        get() = if (!tablet) 5 else if (width >= 1000) 40 else if (width >= 600) 28 else 18

    val homePadding
        get() = if (tablet) screenPadding else 20

    val recommendationColumns
        get() = if (width >= 1000) 4 else 3

    val popularColumns
        get() = if (wideTablet && width >= 900) 2 else 1

    val popularPageSize
        get() = if (wideTablet) 6 else 5

    val libraryColumns
        get() =
            if (!tablet) {
                if (landscape && width >= 700) 3 else 2
            } else if (width >= 700) 4 else if (width >= 560) 3 else 2
}
