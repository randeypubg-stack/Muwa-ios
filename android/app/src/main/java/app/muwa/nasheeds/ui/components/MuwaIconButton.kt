package app.muwa.nasheeds.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.ui.design.MuwaColors
import app.muwa.nasheeds.ui.design.MuwaMotion

@Composable
fun MuwaIconButton(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interactions = remember { MutableInteractionSource() }
    val pressed by interactions.collectIsPressedAsState()
    val scale by
        animateFloatAsState(if (pressed) .91f else 1f, MuwaMotion.press(), label = "button.press")
    IconButton(
        onClick = onClick,
        interactionSource = interactions,
        modifier =
            modifier
                .size(48.dp)
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                }
                .background(Color.White.copy(alpha = .055f), RoundedCornerShape(16.dp)),
    ) {
        Icon(icon, label, tint = MuwaColors.Secondary)
    }
}
