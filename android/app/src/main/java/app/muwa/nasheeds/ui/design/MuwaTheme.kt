package app.muwa.nasheeds.ui.design

import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

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
        content = {
            // Transparent containers inherit their parent's content color.
            // MaterialTheme alone does not establish that default for a Box.
            CompositionLocalProvider(LocalContentColor provides MuwaColors.Text) { content() }
        },
    )
}
