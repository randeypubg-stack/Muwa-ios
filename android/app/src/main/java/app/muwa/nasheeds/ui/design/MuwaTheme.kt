package app.muwa.nasheeds.ui.design

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

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
        content = content,
    )
}
