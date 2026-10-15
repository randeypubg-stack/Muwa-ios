package app.muwa.nasheeds.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Matches the iOS glass surface without blurring text or requiring Android 12. */
fun Modifier.glassPanel(radius: Dp = 26.dp, navigation: Boolean = false): Modifier {
    val shape = RoundedCornerShape(radius)
    return clip(shape)
        .background(
            Brush.linearGradient(
                listOf(
                    Color.White.copy(alpha = if (navigation) .18f else .075f),
                    Color.White.copy(alpha = if (navigation) .10f else .025f),
                )
            )
        )
        .background(MuwaColors.Surface.copy(alpha = if (navigation) .68f else .32f))
        .border(
            .75.dp,
            Brush.linearGradient(
                listOf(Color.White.copy(alpha = .19f), Color.White.copy(alpha = .025f))
            ),
            shape,
        )
}
