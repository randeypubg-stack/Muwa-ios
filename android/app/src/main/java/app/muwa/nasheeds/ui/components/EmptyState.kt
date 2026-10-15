package app.muwa.nasheeds.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.ui.design.*

@Composable
internal fun EmptyState(
    icon: ImageVector,
    title: String,
    message: String,
    actionTitle: String? = null,
    action: (() -> Unit)? = null,
) {
    Column(
        Modifier.fillMaxWidth().glassPanel().padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Box(Modifier.height(108.dp).width(116.dp), contentAlignment = Alignment.Center) {
            Box(
                Modifier.size(92.dp)
                    .graphicsLayer {
                        rotationZ = -12f
                        translationX = -10.dp.toPx()
                        translationY = 3.dp.toPx()
                    }
                    .background(MuwaColors.Blue.copy(alpha = .08f), RoundedCornerShape(26.dp))
            )
            Box(
                Modifier.size(88.dp)
                    .background(
                        Brush.linearGradient(
                            listOf(
                                MuwaColors.Ice.copy(alpha = .18f),
                                MuwaColors.Blue.copy(alpha = .07f),
                            )
                        ),
                        RoundedCornerShape(26.dp),
                    )
                    .border(.75.dp, Color.White.copy(alpha = .12f), RoundedCornerShape(26.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, null, Modifier.size(32.dp), tint = MuwaColors.Ice)
            }
        }
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MuwaColors.Secondary,
            textAlign = TextAlign.Center,
        )
        if (actionTitle != null && action != null)
            Button(
                onClick = action,
                shape = RoundedCornerShape(16.dp),
                contentPadding = PaddingValues(horizontal = 24.dp, vertical = 16.dp),
            ) {
                Text(actionTitle)
            }
    }
}
