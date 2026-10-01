package app.muwa.nasheeds

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.BackHandler
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.core.content.FileProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.Player
import coil.compose.AsyncImage
import kotlinx.coroutines.launch
import org.json.JSONObject
import kotlin.math.abs

class MainActivity : ComponentActivity() {
    companion object { private var launchHasPlayed = false }
    private val notifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState); enableEdgeToEdge()
        val reviewRoute = if (BuildConfig.DEBUG) intent.getStringExtra("review.route") else null
        val showIntro = savedInstanceState == null && (reviewRoute == "launch" || (reviewRoute == null && !launchHasPlayed))
        if (reviewRoute == null) launchHasPlayed = true
        setContent { MaterialTheme(colorScheme = darkColorScheme(background=Color(0xFF010102),surface=Color(0xFF10141B),primary=Color(0xFFD9E8FF))) {
            MuwaLaunchHost(showIntro = showIntro) {
                MuwaApp(initialRoute = reviewRoute?.takeUnless { it == "launch" } ?: "home", requestNotifications = { if (Build.VERSION.SDK_INT >= 33) notifications.launch(Manifest.permission.POST_NOTIFICATIONS) })
            }
        } }
    }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun MuwaApp(model: MuwaModel = viewModel(), initialRoute: String = "home", requestNotifications: () -> Unit = {}) {
    var route by rememberSaveableState(if(initialRoute == "player") "home" else initialRoute)
    var expanded by rememberSaveableState(initialRoute == "player")
    var newPlaylist by remember { mutableStateOf(false) }
    var playlistName by remember { mutableStateOf("") }
    var addingTrack by remember { mutableStateOf<Track?>(null) }
    val context = LocalContext.current
    LaunchedEffect(model.controller) {
        if (BuildConfig.DEBUG && initialRoute == "player" && model.controller != null && model.track == null) {
            model.play(model.library.catalog.first(), autoplay = false)
        }
    }
    BackHandler(route !in listOf("home","library","profile") || expanded) { if (expanded) expanded = false else route = if (route in listOf("premium","promo","settings","auth")) "profile" else "library" }
    val selected = if (route == "home" || route == "search") "home" else if (route in listOf("profile","premium","promo","settings","auth")) "profile" else "library"
    val play: (Track) -> Unit = { model.play(it); requestNotifications() }
    Scaffold(containerColor=MaterialTheme.colorScheme.background, bottomBar = {
        Column(Modifier.navigationBarsPadding().padding(horizontal=8.dp), verticalArrangement=Arrangement.spacedBy(8.dp)) {
            if (model.track != null && !expanded) {
                Surface(Modifier.fillMaxWidth().testTag("mini-player").clickable { expanded = true },shape=RoundedCornerShape(24.dp),color=Color(0xEE18202A)) {
                    Row(Modifier.padding(8.dp),verticalAlignment=Alignment.CenterVertically) {
                        Cover(model.track!!, Modifier.size(42.dp)); Column(Modifier.weight(1f).padding(horizontal=12.dp)) { Text(model.track!!.title,maxLines=1); Text(model.track!!.artist,fontSize=11.sp,color=Color.Gray,maxLines=1) }
                        IconButton(onClick=model::toggle) { Icon(if(model.playing) Icons.Default.Pause else Icons.Default.PlayArrow,"Воспроизведение") }
                        IconButton(onClick=model::next) { Icon(Icons.Default.SkipNext,"Следующий") }
                    }
                }
            }
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(Color(0xEE171D26)).pointerInput(Unit) {
                detectDragGesturesAfterLongPress { change,_ ->
                    val index = (change.position.x / (size.width / 3f)).toInt().coerceIn(0,2); route = listOf("home","library","profile")[index]; expanded = false; change.consume()
                }
            },horizontalArrangement=Arrangement.SpaceEvenly) {
                listOf(Triple("home","Главная",Icons.Default.Home),Triple("library","Библиотека",Icons.Default.LibraryMusic),Triple("profile","Профиль",Icons.Default.Person)).forEach { (id,title,icon) ->
                    NavigationBarItem(selected=selected==id,onClick={route=id; expanded=false},icon={Icon(icon,title)},label={Text(title,fontSize=11.sp)},modifier=Modifier.testTag("tab.$id"))
                }
            }
        }
    },topBar={ if (!expanded) TopAppBar(title={Text(when { route.startsWith("playlist:") -> model.library.playlists.firstOrNull { it.id == route.substringAfter(':') }?.name ?: "Плейлист"; else -> mapOf("home" to "Главная","library" to "Библиотека","profile" to "Профиль","search" to "Поиск","queue" to "Очередь","downloads" to "Загрузки","favorites" to "Избранное","history" to "Недавние","premium" to "Muwa Premium","promo" to "Промокод","settings" to "Настройки","auth" to "Аккаунт","subtitles" to "Субтитры","publication" to "Публикация")[route] ?: "Muwa" })}, actions={
        IconButton(onClick={route="search"}) {Icon(Icons.Default.Search,"Поиск")}
    },colors=TopAppBarDefaults.topAppBarColors(containerColor=MaterialTheme.colorScheme.background)) }) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when(route) {
                "home" -> LazyColumn(Modifier.fillMaxSize().padding(horizontal=16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                    if (model.resumeCandidate != null && model.track == null) item {
                        Card { Column(Modifier.padding(16.dp)) { Text("Продолжить прослушивание",style=MaterialTheme.typography.titleMedium); Row { TextButton(onClick={model.resume(); requestNotifications()}) {Text("Продолжить")}; TextButton(onClick=model::dismissResume) {Text("Закрыть")} } } }
                    }
                    item { Text("Нашиды без музыки",color=Color.Gray); Spacer(Modifier.height(8.dp)); Text("Популярное",style=MaterialTheme.typography.headlineSmall) }
                    items(model.library.catalog,key={it.id}) { TrackRow(model,it,play,{ addingTrack = it }) }
                    item { Text("На несколько минут",style=MaterialTheme.typography.titleLarge) }
                    items(model.library.catalog.filter { it.duration <= 180 },key={"short-${it.id}"}) { TrackRow(model,it,play,{ addingTrack = it }) }
                    item { Text("Слушать подольше",style=MaterialTheme.typography.titleLarge) }
                    items(model.library.catalog.filter { it.duration > 180 },key={"long-${it.id}"}) { TrackRow(model,it,play,{ addingTrack = it }) }
                }
                "library" -> LazyColumn(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                    item { ActionCard("Избранное",Icons.Default.Favorite) {route="favorites"} }
                    item { ActionCard("Недавно прослушано",Icons.Default.History) {route="history"} }
                    item { ActionCard("Загрузки",Icons.Default.Download) {route="downloads"} }
                    item { ActionCard("Очередь",Icons.AutoMirrored.Filled.QueueMusic) {route="queue"} }
                    item { ActionCard("Опубликовать нашид",Icons.Default.Upload) {route="publication"} }
                    item { Text("Мои плейлисты",style=MaterialTheme.typography.titleLarge); TextButton(onClick={newPlaylist=true}) {Text("Создать плейлист")} }
                    items(model.library.playlists,key={it.id}) { playlist ->
                        Row(verticalAlignment=Alignment.CenterVertically) { TextButton(onClick={route="playlist:${playlist.id}"},modifier=Modifier.weight(1f)) {Text("${playlist.name} · ${playlist.ids.size}")}; IconButton(onClick={model.library.deletePlaylist(playlist.id)}) {Icon(Icons.Default.Delete,"Удалить плейлист")} }
                    }
                }
                "profile" -> LazyColumn(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
                    item { Image(painterResource(R.drawable.app_mark),"Muwa",Modifier.size(80.dp).clip(RoundedCornerShape(22.dp))); Text(model.user?.optString("displayName") ?: "Гость",style=MaterialTheme.typography.headlineSmall); Text(model.user?.optString("email") ?: "Войдите, чтобы управлять аккаунтом",color=Color.Gray) }
                    if (model.user==null) item { Button(onClick={route="auth"}) {Text("Войти или создать аккаунт")} }
                    item { ActionCard("Premium",Icons.Default.WorkspacePremium) {route="premium"} }
                    item { ActionCard("Промокод",Icons.Default.CardGiftcard) {route="promo"} }
                    item { ActionCard("Настройки и диагностика",Icons.Default.Settings) {route="settings"} }
                    if(model.user!=null) item { TextButton(onClick=model::logout,enabled=!model.busy) {Text("Выйти из аккаунта")} }
                    item { Text("Muwa · Нашиды без музыки\nВерсия ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",fontSize=12.sp,color=Color.Gray) }
                }
                "search" -> SearchScreen(model,play,{addingTrack=it})
                "favorites","history","downloads","queue" -> {
                    val tracks = when(route) {"favorites" -> model.library.tracks(model.library.favorites); "history" -> model.library.tracks(model.library.history); "downloads" -> model.library.catalog.filter { it.id in model.downloads.downloaded }; else -> model.library.tracks(model.library.queue)}
                    LazyColumn(Modifier.padding(horizontal=16.dp)) {
                        if (tracks.isEmpty()) item { Text("Пока пусто",Modifier.padding(30.dp),color=Color.Gray) }
                        items(tracks,key={it.id}) { t ->
                            TrackRow(model,t,play,{addingTrack=it})
                            if(route=="queue") Row { TextButton(onClick={model.moveQueue(t.id,-1)}) {Text("Выше")}; TextButton(onClick={model.moveQueue(t.id,1)}) {Text("Ниже")}; TextButton(onClick={model.removeQueue(t.id)}) {Text("Удалить из очереди")} }
                            if(route=="downloads") TextButton(onClick={runCatching {model.downloads.remove(t)}.onFailure {model.error=it.message}}) {Text("Удалить загрузку")}
                        }
                    }
                }
                "premium" -> PremiumScreen(model, {route="promo"}, {route="auth"})
                "promo" -> PromoScreen(model) {route="auth"}
                "auth" -> AuthScreen(model)
                "settings" -> SettingsScreen(model)
                "subtitles" -> SubtitleScreen(model)
                "publication" -> PublicationScreen(model)
                else -> if(route.startsWith("playlist:")) {
                    val id=route.substringAfter(':'); val list=model.library.playlists.firstOrNull {it.id==id}
                    LazyColumn(Modifier.padding(16.dp)) { if(list?.ids.isNullOrEmpty()) item {Text("Добавьте нашиды через меню ⋮")}; items(model.library.tracks(list?.ids.orEmpty()),key={it.id}) { t -> TrackRow(model,t,play,{addingTrack=it}); TextButton(onClick={model.library.togglePlaylist(id,t)}) {Text("Убрать из плейлиста")} } }
                }
            }
        }
    }
    if (expanded && model.track != null) PlayerSheet(model,onClose={expanded=false},onQueue={expanded=false;route="queue"},onSubtitles={model.loadSubtitles();expanded=false;route="subtitles"},onPlaylist={addingTrack=model.track})
    if (model.error != null) AlertDialog(onDismissRequest={model.error=null},title={Text("Не удалось выполнить действие")},text={Text(model.error!!)},confirmButton={TextButton(onClick={model.error=null}) {Text("OK")}})
    if (newPlaylist) AlertDialog(onDismissRequest={newPlaylist=false},title={Text("Новый плейлист")},text={OutlinedTextField(playlistName,{playlistName=it},label={Text("Название")})},confirmButton={TextButton(onClick={model.library.createPlaylist(playlistName);playlistName="";newPlaylist=false}) {Text("Создать")}},dismissButton={TextButton(onClick={newPlaylist=false}) {Text("Отмена")}})
    if (addingTrack != null) ModalBottomSheet(onDismissRequest={addingTrack=null}) {
        Column(Modifier.padding(24.dp)) {
            Text("Добавить в плейлист",style=MaterialTheme.typography.titleLarge)
            model.library.playlists.forEach { p -> TextButton(onClick={model.library.togglePlaylist(p.id,addingTrack!!);addingTrack=null}) {Text(p.name)} }
            TextButton(onClick={newPlaylist=true;addingTrack=null}) {Text("Создать плейлист")}
        }
    }
}
@Composable fun <T> rememberSaveableState(initial: T): MutableState<T> = androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(initial) }
@Composable fun Cover(track: Track, modifier: Modifier) { AsyncImage(track.artwork,contentDescription="Обложка ${track.title}",modifier=modifier.clip(RoundedCornerShape(20.dp)),placeholder=painterResource(R.drawable.app_mark),error=painterResource(R.drawable.app_mark),contentScale=androidx.compose.ui.layout.ContentScale.Crop) }
@Composable fun ActionCard(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, action: () -> Unit) { Card(onClick=action,modifier=Modifier.fillMaxWidth()) { Row(Modifier.padding(20.dp),verticalAlignment=Alignment.CenterVertically) {Icon(icon,null); Text(title,Modifier.weight(1f).padding(start=16.dp)); Icon(Icons.AutoMirrored.Filled.ArrowForward,null)} } }
@Composable fun TrackRow(model: MuwaModel, track: Track, play: (Track)->Unit, playlist: (Track)->Unit) {
    var menu by remember {mutableStateOf(false)}
    val context=LocalContext.current
    Row(Modifier.fillMaxWidth().padding(vertical=8.dp),verticalAlignment=Alignment.CenterVertically) {
        Row(Modifier.weight(1f).clickable {play(track)}.padding(vertical=6.dp),verticalAlignment=Alignment.CenterVertically) {Cover(track,Modifier.size(52.dp)); Column(Modifier.weight(1f).padding(horizontal=12.dp)) {Text(track.title,maxLines=1); Text(track.artist,fontSize=12.sp,color=Color.Gray,maxLines=1)}; Text(if(model.track?.id==track.id && model.playing) "▥" else formatTime(track.duration*1000),fontSize=11.sp,color=Color.Gray)}
        Box {IconButton(onClick={menu=true}) {Icon(Icons.Default.MoreVert,"Действия ${track.title}")}; DropdownMenu(menu,{menu=false}) {
            DropdownMenuItem(text={Text(if(track.id in model.library.favorites) "Убрать из избранного" else "В избранное")},onClick={model.library.like(track);menu=false})
            DropdownMenuItem(text={Text("Добавить в плейлист")},onClick={playlist(track);menu=false})
            DropdownMenuItem(text={Text("Играть следующим")},onClick={model.addQueue(track,true);menu=false})
            DropdownMenuItem(text={Text("Добавить в очередь")},onClick={model.addQueue(track);menu=false})
            DropdownMenuItem(text={Text(if(track.id in model.downloads.downloaded) "Удалить загрузку" else if(model.downloads.progress.containsKey(track.id)) "Отменить скачивание" else "Скачать MP3")},onClick={menu=false;runCatching { if(track.id in model.downloads.downloaded) model.downloads.remove(track) else if(model.downloads.progress.containsKey(track.id)) model.downloads.cancel(track) else model.downloads.download(track) {model.error=it.message} }.onFailure {model.error=it.message}})
            DropdownMenuItem(text={Text("Поделиться")},onClick={menu=false; context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT,"${track.title}\n${track.audio}"),"Поделиться нашидом"))})
        }}
    }
    model.downloads.progress[track.id]?.let { LinearProgressIndicator(progress={it},modifier=Modifier.fillMaxWidth()) }
}
@Composable fun SearchScreen(model: MuwaModel,play: (Track)->Unit, playlist: (Track)->Unit) {
    var query by rememberSaveableState(""); var recent by rememberSaveableState(false)
    val rows = if(recent) model.library.tracks(model.library.history) else model.library.catalog
    val results = rows.filter {it.title.contains(query.trim(),true)||it.artist.contains(query.trim(),true)}
    Column(Modifier.padding(16.dp)) { OutlinedTextField(query,{query=it},label={Text("Название или автор")},modifier=Modifier.fillMaxWidth()); Row {FilterChip(recent,{recent=!recent},label={Text("Недавние")})}; LazyColumn { if(results.isEmpty()) item {Text("Ничего не найдено",Modifier.padding(24.dp))}; items(results,key={it.id}) {TrackRow(model,it,play,playlist)} } }
}
