package app.muwa.nasheeds.ui.components

fun trackCount(count: Int): String {
    val ending =
        when {
            count % 100 in 11..14 -> "нашидов"
            count % 10 == 1 -> "нашид"
            count % 10 in 2..4 -> "нашида"
            else -> "нашидов"
        }
    return "$count $ending"
}
