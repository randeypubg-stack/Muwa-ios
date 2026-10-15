package app.muwa.nasheeds.ui.design

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.unit.dp

@Composable
fun MuwaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme =
            darkColorScheme(
                background = MuwaColors.Background,
                surface = MuwaColors.Surface,
                primary = MuwaColors.Ice,
                onPrimary = MuwaColors.Background,
                onBackground = MuwaColors.Text,
                onSurface = MuwaColors.Text,
                onSurfaceVariant = MuwaColors.Secondary,
            ),
        typography = MuwaTypography,
        shapes =
            Shapes(
                extraSmall = RoundedCornerShape(12.dp),
                small = RoundedCornerShape(16.dp),
                medium = RoundedCornerShape(20.dp),
                large = RoundedCornerShape(26.dp),
                extraLarge = RoundedCornerShape(28.dp),
            ),
        content = {
            // Transparent containers inherit their parent's content color.
            // MaterialTheme alone does not establish that default for a Box.
            CompositionLocalProvider(LocalContentColor provides MuwaColors.Text) { content() }
        },
    )
}
