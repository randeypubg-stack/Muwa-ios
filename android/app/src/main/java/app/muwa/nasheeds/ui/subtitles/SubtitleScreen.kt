package app.muwa.nasheeds.ui.subtitles

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.ui.design.MuwaMotion
import app.muwa.nasheeds.ui.design.rememberAmbientMotionAllowed

/** The existing manual-caption reader, with stable Arabic typography and
 * interruptible focus. No synthetic word timing or recognition request. */
@Composable
fun SubtitleScreen(model: MuwaModel) {
    val trackID = model.track?.id
    var language by rememberSaveable(trackID) { mutableStateOf("ar") }
    var follow by rememberSaveable(trackID) { mutableStateOf(true) }
    val listState = rememberLazyListState()
    val motionAllowed = rememberAmbientMotionAllowed()
    var positioned by remember(trackID) { mutableStateOf(false) }
    val active = model.subtitles.indexOfFirst {
        model.position / 1000.0 >= it.optDouble("start") &&
            model.position / 1000.0 < it.optDouble("end")
    }
    LaunchedEffect(active, follow, motionAllowed, trackID) {
        if (follow && active >= 0) {
            if (positioned && motionAllowed) listState.animateScrollToItem(active)
            else listState.scrollToItem(active)
            positioned = true
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize().testTag("subtitles.screen")) {
      val compact = maxHeight < 260.dp && maxWidth >= 440.dp
      Column(Modifier.padding(horizontal = 16.dp, vertical = if (compact) 0.dp else 16.dp)) {
        Row {
            listOf("ar", "ru", "en").forEach { lang ->
                TextButton(onClick = { language = lang }, modifier = if (compact) Modifier else Modifier.weight(1f),
                    contentPadding = PaddingValues(horizontal = 4.dp)) { Text(lang.uppercase()) }
            }
            if (compact) {
                Spacer(Modifier.weight(1f))
                Text("Следить", Modifier.padding(top = 12.dp), style = MaterialTheme.typography.bodyMedium)
                Switch(follow, { follow = it }, Modifier.testTag("subtitles.follow"))
                TextButton(onClick = model::loadSubtitles, enabled = !model.subtitleLoading) { Text("Обновить") }
            }
        }
        if (!compact) Row {
            Text("Следить за воспроизведением", Modifier.weight(1f).padding(top = 12.dp),
                style = MaterialTheme.typography.bodyMedium)
            Switch(follow, { follow = it }, Modifier.testTag("subtitles.follow"))
        }
        if (!compact || model.subtitles.isEmpty()) Text(model.subtitleStatus, color = Color.Gray)
        if (!compact) TextButton(onClick = model::loadSubtitles, enabled = !model.subtitleLoading) {
            Text(if (model.subtitleLoading) "Загрузка…" else "Обновить текст")
        }
        if (model.subtitleLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
        LazyColumn(
            state = listState,
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.weight(1f).testTag("subtitles.list").pointerInput(trackID) {
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent()
                        if (event.changes.any { it.pressed && it.position != it.previousPosition }) follow = false
                    }
                }
            },
        ) {
            items(model.subtitles.size, key = { index ->
                val item = model.subtitles[index]
                "$trackID|${item.optDouble("start")}|$index"
            }) { index ->
                val item = model.subtitles[index]
                val focused = index == active
                val textColor by animateColorAsState(
                    if (focused) Color.White else Color.White.copy(alpha = 0.42f),
                    if (motionAllowed) MuwaMotion.subtitleFocus() else snap(), label = "subtitle.text",
                )
                val surface by animateColorAsState(
                    Color.White.copy(alpha = if (focused) 0.055f else 0f),
                    if (motionAllowed) MuwaMotion.subtitleFocus() else snap(), label = "subtitle.focus",
                )
                val focusScale by animateFloatAsState(
                    if (focused || !motionAllowed) 1f else 0.97f,
                    if (motionAllowed) MuwaMotion.subtitleFocus() else snap(), label = "subtitle.depth",
                )
                Column(
                    Modifier.fillMaxWidth().testTag("subtitle.line.$index")
                        .semantics { selected = focused }
                        .graphicsLayer {
                            scaleX = focusScale; scaleY = focusScale
                            transformOrigin = TransformOrigin(1f, 0.5f)
                        }
                        .clip(RoundedCornerShape(22.dp))
                        .background(Brush.horizontalGradient(listOf(Color.Transparent, surface)))
                        .clickable {
                            follow = false
                            model.seek((item.optDouble("start") * 1000).toLong())
                        }.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        item.optString("ar"), Modifier.fillMaxWidth(),
                        style = MaterialTheme.typography.titleLarge.copy(
                            fontSize = 23.sp, fontWeight = FontWeight.SemiBold,
                            textDirection = TextDirection.ContentOrRtl),
                        textAlign = TextAlign.Right, color = textColor,
                    )
                    if (language != "ar") Text(
                        item.optString(language), Modifier.fillMaxWidth(),
                        style = MaterialTheme.typography.bodyLarge.copy(textDirection = TextDirection.ContentOrLtr),
                        color = textColor.copy(alpha = textColor.alpha * 0.75f),
                    )
                }
            }
        }
      }
    }
}
