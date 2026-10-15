package app.muwa.nasheeds.ui.navigation

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.ui.components.Cover
import app.muwa.nasheeds.ui.design.*
import kotlin.math.roundToInt

/** The root owns the physical anchor; this shared chrome never chooses an offset. */
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
    val slots = listOf("home", "player", "library", "profile")
    val titles = listOf("Главная", "Плеер", "Библиотека", "Профиль")
    val icons =
        listOf(
            Icons.Default.Home,
            Icons.Default.PlayArrow,
            Icons.AutoMirrored.Filled.LibraryBooks,
            Icons.Default.Person,
        )
    val active = if (expanded) 1 else slots.indexOf(selected).coerceAtLeast(0)
    val motion = rememberAmbientMotionAllowed()
    val highlight by
        animateFloatAsState(
            active.toFloat(),
            if (motion) spring(dampingRatio = .94f, stiffness = 700f) else snap(),
            label = "tab.highlight",
        )
    val navigate by rememberUpdatedState(onNavigate)
    val expand by rememberUpdatedState(onExpandPlayer)
    Column(
        modifier
            .windowInsetsPadding(
                systemInsets.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom)
            )
            .padding(start = 5.dp, end = 5.dp, bottom = extraBottomPadding),
        verticalArrangement = Arrangement.spacedBy(BottomNavigationLayout.playerGapDp.dp),
    ) {
        val track = model.track
        if (track != null && !expanded) {
            Column(
                Modifier.fillMaxWidth()
                    .height(BottomNavigationLayout.miniPlayerHeightDp.dp)
                    .testTag("mini-player")
                    .glassPanel(27.dp, navigation = true)
                    .clickable(onClick = onExpandPlayer)
            ) {
                Row(
                    Modifier.weight(1f).padding(start = 7.dp, end = 7.dp, top = 5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Cover(track, Modifier.size(42.dp), 13.dp)
                    Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                        Text(
                            track.title,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            track.artist,
                            fontSize = 10.sp,
                            color = MuwaColors.Secondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    IconButton(
                        onClick = model::toggle,
                        modifier =
                            Modifier.size(40.dp)
                                .background(Color.White.copy(alpha = .055f), CircleShape),
                    ) {
                        Icon(
                            if (model.playing) Icons.Default.Pause else Icons.Default.PlayArrow,
                            "Воспроизведение",
                            Modifier.size(22.dp),
                        )
                    }
                    Spacer(Modifier.width(4.dp))
                    IconButton(
                        onClick = model::next,
                        modifier =
                            Modifier.size(40.dp)
                                .background(Color.White.copy(alpha = .085f), CircleShape),
                    ) {
                        Icon(Icons.Default.FastForward, "Следующий", Modifier.size(22.dp))
                    }
                }
                val progress =
                    if (model.duration > 0)
                        (model.position.toFloat() / model.duration).coerceIn(0f, 1f)
                    else 0f
                Box(
                    Modifier.padding(horizontal = 16.dp, vertical = 3.dp)
                        .fillMaxWidth()
                        .height(2.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = .12f))
                ) {
                    Box(
                        Modifier.fillMaxWidth(progress)
                            .fillMaxHeight()
                            .background(Color.White.copy(alpha = .72f))
                    )
                }
            }
        }
        BoxWithConstraints(
            Modifier.fillMaxWidth()
                .height(BottomNavigationLayout.barHeightDp.dp)
                .testTag("bottom-navigation")
                .glassPanel(28.dp, navigation = true)
                .pointerInput(Unit) {
                    var previous = -1
                    detectHorizontalDragGestures(onDragStart = { previous = -1 }) { change, _ ->
                        val slot = (change.position.x / (size.width / 4f)).toInt().coerceIn(0, 3)
                        if (slot != previous) {
                            previous = slot
                            if (slot == 1) expand() else navigate(slots[slot])
                        }
                        change.consume()
                    }
                }
                .padding(5.dp)
        ) {
            val slotWidth = maxWidth / 4
            Box(
                Modifier.offset { IntOffset((slotWidth.toPx() * highlight).roundToInt(), 0) }
                    .width(slotWidth)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(21.dp))
                    .background(
                        Brush.linearGradient(
                            listOf(Color.White.copy(alpha = .19f), Color.White.copy(alpha = .055f))
                        )
                    )
                    .border(1.dp, Color.White.copy(alpha = .12f), RoundedCornerShape(21.dp))
            )
            Row(Modifier.fillMaxSize()) {
                slots.forEachIndexed { index, id ->
                    Column(
                        Modifier.weight(1f)
                            .fillMaxHeight()
                            .testTag("tab.$id")
                            .selectable(
                                selected = index == active,
                                role = Role.Tab,
                                onClick = {
                                    if (id == "player") onExpandPlayer() else onNavigate(id)
                                },
                            ),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(
                            icons[index],
                            null,
                            Modifier.size(20.dp),
                            tint = Color.White.copy(alpha = if (index == active) 1f else .66f),
                        )
                        Text(
                            titles[index],
                            fontSize = 8.5.sp,
                            lineHeight = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = if (index == active) 1f else .66f),
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}
