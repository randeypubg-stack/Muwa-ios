package app.muwa.nasheeds.ui.navigation

import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.ui.components.Cover
import app.muwa.nasheeds.ui.design.BottomNavigationLayout
import app.muwa.nasheeds.ui.design.MuwaColors

/** Navigation and mini-player share insets measured once by the app root. */
@Composable
internal fun AppBottomBar(
    model: MuwaModel,
    selected: String,
    expanded: Boolean,
    systemInsets: WindowInsets,
    extraBottomPadding: Dp,
    onNavigate: (String) -> Unit,
    onExpandPlayer: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .windowInsetsPadding(
                systemInsets.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom)
            )
            .padding(start = 8.dp, end = 8.dp, bottom = extraBottomPadding),
        verticalArrangement = Arrangement.spacedBy(BottomNavigationLayout.playerGapDp.dp),
    ) {
        if (model.track != null && !expanded) {
            Surface(
                Modifier.fillMaxWidth().testTag("mini-player").clickable { onExpandPlayer() },
                shape = RoundedCornerShape(24.dp),
                color = Color(0xEE18202A),
            ) {
                Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Cover(model.track!!, Modifier.size(42.dp))
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                        Text(model.track!!.title, maxLines = 1)
                        Text(
                            model.track!!.artist,
                            fontSize = 11.sp,
                            color = Color.Gray,
                            maxLines = 1,
                        )
                    }
                    IconButton(onClick = model::toggle) {
                        Icon(
                            if (model.playing) Icons.Default.Pause else Icons.Default.PlayArrow,
                            "Воспроизведение",
                        )
                    }
                    IconButton(onClick = model::next) { Icon(Icons.Default.SkipNext, "Следующий") }
                }
            }
        }
        Row(
            Modifier.fillMaxWidth()
                .testTag("bottom-navigation")
                .clip(RoundedCornerShape(28.dp))
                .background(Color(0xEE171D26))
                .pointerInput(Unit) {
                    detectDragGesturesAfterLongPress { change, _ ->
                        val index = (change.position.x / (size.width / 3f)).toInt().coerceIn(0, 2)
                        onNavigate(listOf("home", "library", "profile")[index])
                        change.consume()
                    }
                },
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            listOf(
                    Triple("home", "Главная", Icons.Default.Home),
                    Triple("library", "Библиотека", Icons.Default.LibraryMusic),
                    Triple("profile", "Профиль", Icons.Default.Person),
                )
                .forEach { (id, title, icon) ->
                    NavigationBarItem(
                        colors =
                            NavigationBarItemDefaults.colors(
                                selectedIconColor = MuwaColors.Ice,
                                selectedTextColor = MuwaColors.Text,
                                indicatorColor = MuwaColors.Ice.copy(alpha = .10f),
                                unselectedIconColor = MuwaColors.Secondary,
                                unselectedTextColor = MuwaColors.Secondary,
                            ),
                        selected = selected == id,
                        onClick = { onNavigate(id) },
                        icon = { Icon(icon, title) },
                        label = { Text(title, fontSize = 11.sp) },
                        modifier = Modifier.testTag("tab.$id"),
                    )
                }
        }
    }
}
