package app.muwa.nasheeds

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import app.muwa.nasheeds.ui.components.*
import app.muwa.nasheeds.ui.design.*
import app.muwa.nasheeds.ui.home.HomeScreen
import app.muwa.nasheeds.ui.library.LibraryScreen
import app.muwa.nasheeds.ui.profile.ProfileScreen
import app.muwa.nasheeds.ui.queue.QueueScreen
import app.muwa.nasheeds.ui.search.SearchScreen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MuwaApp(
    model: MuwaModel = viewModel(),
    initialRoute: String = "home",
    requestNotifications: () -> Unit = {},
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, model) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START) model.refreshCatalog()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    var route by rememberSaveableState(if (initialRoute == "player") "home" else initialRoute)
    var expanded by rememberSaveableState(initialRoute == "player")
    var newPlaylist by remember { mutableStateOf(false) }
    var playlistName by remember { mutableStateOf("") }
    var addingTrack by remember { mutableStateOf<Track?>(null) }
    LaunchedEffect(model.controller) {
        if (
            BuildConfig.DEBUG &&
                initialRoute == "player" &&
                model.controller != null &&
                model.track == null
        ) {
            model.library.catalog.firstOrNull()?.let { model.play(it, autoplay = false) }
        }
    }
    BackHandler(route !in listOf("home", "library", "profile") || expanded) {
        if (expanded) expanded = false
        else
            route =
                if (route.startsWith("collection:")) "home"
                else if (route in listOf("premium", "promo", "settings", "auth")) "profile"
                else "library"
    }
    val selected =
        if (route == "home" || route == "search" || route.startsWith("collection:")) "home"
        else if (route in listOf("profile", "premium", "promo", "settings", "auth")) "profile"
        else "library"
    val play: (Track) -> Unit = {
        model.play(it)
        requestNotifications()
    }
    Box(Modifier.fillMaxSize()) {
        MuwaAmbientBackground(Modifier.fillMaxSize())
        Scaffold(
            modifier = if (expanded) Modifier.clearAndSetSemantics {} else Modifier,
            containerColor = Color.Transparent,
            bottomBar = {
                Column(
                    Modifier.navigationBarsPadding().padding(horizontal = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (model.track != null && !expanded) {
                        Surface(
                            Modifier.fillMaxWidth().testTag("mini-player").clickable {
                                expanded = true
                            },
                            shape = RoundedCornerShape(24.dp),
                            color = Color(0xEE18202A),
                        ) {
                            Row(
                                Modifier.padding(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
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
                                        if (model.playing) Icons.Default.Pause
                                        else Icons.Default.PlayArrow,
                                        "Воспроизведение",
                                    )
                                }
                                IconButton(onClick = model::next) {
                                    Icon(Icons.Default.SkipNext, "Следующий")
                                }
                            }
                        }
                    }
                    Row(
                        Modifier.fillMaxWidth()
                            .clip(RoundedCornerShape(28.dp))
                            .background(Color(0xEE171D26))
                            .pointerInput(Unit) {
                                detectDragGesturesAfterLongPress { change, _ ->
                                    val index =
                                        (change.position.x / (size.width / 3f))
                                            .toInt()
                                            .coerceIn(0, 2)
                                    route = listOf("home", "library", "profile")[index]
                                    expanded = false
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
                                    onClick = {
                                        route = id
                                        expanded = false
                                    },
                                    icon = { Icon(icon, title) },
                                    label = { Text(title, fontSize = 11.sp) },
                                    modifier = Modifier.testTag("tab.$id"),
                                )
                            }
                    }
                }
            },
            topBar = {
                if (!expanded)
                    TopAppBar(
                        title = {
                            Text(
                                when {
                                    route.startsWith("collection:") ->
                                        when (route.substringAfter(':')) {
                                            "short" -> "На несколько минут"
                                            "long" -> "Слушать подольше"
                                            else -> "Вся коллекция"
                                        }
                                    route.startsWith("playlist:") ->
                                        model.library.playlists
                                            .firstOrNull { it.id == route.substringAfter(':') }
                                            ?.name ?: "Плейлист"
                                    else ->
                                        mapOf(
                                            "home" to "Главная",
                                            "library" to "Библиотека",
                                            "profile" to "Профиль",
                                            "search" to "Поиск",
                                            "queue" to "Очередь",
                                            "downloads" to "Загрузки",
                                            "favorites" to "Избранное",
                                            "history" to "Недавние",
                                            "premium" to "Muwa Premium",
                                            "promo" to "Промокод",
                                            "settings" to "Настройки",
                                            "auth" to "Аккаунт",
                                            "subtitles" to "Субтитры",
                                            "publication" to "Публикация",
                                        )[route] ?: "Muwa"
                                }
                            )
                        },
                        actions = {
                            IconButton(onClick = { route = "search" }) {
                                Icon(Icons.Default.Search, "Поиск")
                            }
                        },
                        colors =
                            TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
                    )
            },
        ) { padding ->
            Box(Modifier.fillMaxSize().padding(padding)) {
                when (route) {
                    "home" ->
                        HomeScreen(
                            model,
                            { model.play(it, model.library.catalog); requestNotifications() },
                            { addingTrack = it },
                            { route = "collection:$it" },
                            {
                                model.resume()
                                requestNotifications()
                            },
                        )
                    "queue" -> QueueScreen(model, play)
                    "library" -> LibraryScreen(model, { route = it }, { newPlaylist = true })
                    "profile" -> ProfileScreen(model) { route = it }
                    "search" -> SearchScreen(model, play, { addingTrack = it })
                    "favorites",
                    "history",
                    "downloads" -> {
                        val tracks =
                            when (route) {
                                "favorites" -> model.library.tracks(model.library.favorites)
                                "history" -> model.library.tracks(model.library.history)
                                "downloads" ->
                                    model.library.tracks(model.downloads.downloaded).filter {
                                        model.downloads.local(it) != null
                                    }
                                else -> model.library.tracks(model.library.queue)
                            }
                        LazyColumn(Modifier.padding(horizontal = 16.dp)) {
                            if (tracks.isEmpty())
                                item {
                                    Text("Пока пусто", Modifier.padding(30.dp), color = Color.Gray)
                                }
                            items(tracks, key = { it.id }) { t ->
                                TrackRow(model, t, play, { addingTrack = it })
                                if (route == "downloads")
                                    TextButton(
                                        onClick = {
                                            runCatching { model.downloads.remove(t) }
                                                .onFailure { model.error = it.message }
                                        }
                                    ) {
                                        Text("Удалить загрузку")
                                    }
                            }
                        }
                    }
                    "premium" -> PremiumScreen(model, { route = "promo" }, { route = "auth" })
                    "promo" -> PromoScreen(model) { route = "auth" }
                    "auth" -> AuthScreen(model)
                    "settings" -> SettingsScreen(model)
                    "subtitles" -> SubtitleScreen(model)
                    "publication" -> PublicationScreen(model)
                    else ->
                        if (route.startsWith("collection:")) {
                            val tracks =
                                when (route.substringAfter(':')) {
                                    "short" -> model.library.catalog.filter { it.duration <= 180 }
                                    "long" -> model.library.catalog.filter { it.duration > 180 }
                                    else -> model.library.catalog
                                }
                            LazyColumn(
                                Modifier.padding(horizontal = 20.dp),
                                contentPadding = PaddingValues(bottom = 24.dp),
                            ) {
                                items(tracks, key = { it.id }) {
                                    TrackRow(model, it, { t -> model.play(t, tracks); requestNotifications() }, { addingTrack = it })
                                }
                            }
                        } else if (route.startsWith("playlist:")) {
                            val id = route.substringAfter(':')
                            val list = model.library.playlists.firstOrNull { it.id == id }
                            LazyColumn(Modifier.padding(16.dp)) {
                                if (list?.ids.isNullOrEmpty())
                                    item { Text("Добавьте нашиды через меню ⋮") }
                                items(model.library.tracks(list?.ids.orEmpty()), key = { it.id }) {
                                    t ->
                                    TrackRow(model, t, play, { addingTrack = it })
                                    TextButton(onClick = { model.library.togglePlaylist(id, t) }) {
                                        Text("Убрать из плейлиста")
                                    }
                                }
                            }
                        }
                }
            }
        }
        if (expanded && model.track != null)
            PlayerSheet(
                model,
                onClose = { expanded = false },
                onQueue = {
                    expanded = false
                    route = "queue"
                },
                onSubtitles = {
                    model.loadSubtitles()
                    expanded = false
                    route = "subtitles"
                },
                onPlaylist = { addingTrack = model.track },
            )
    }
    if (model.error != null)
        AlertDialog(
            onDismissRequest = { model.error = null },
            title = { Text("Не удалось выполнить действие") },
            text = { Text(model.error!!) },
            confirmButton = { TextButton(onClick = { model.error = null }) { Text("OK") } },
        )
    if (newPlaylist)
        AlertDialog(
            onDismissRequest = { newPlaylist = false },
            title = { Text("Новый плейлист") },
            text = {
                OutlinedTextField(playlistName, { playlistName = it }, label = { Text("Название") })
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        model.library.createPlaylist(playlistName)
                        playlistName = ""
                        newPlaylist = false
                    }
                ) {
                    Text("Создать")
                }
            },
            dismissButton = { TextButton(onClick = { newPlaylist = false }) { Text("Отмена") } },
        )
    if (addingTrack != null)
        ModalBottomSheet(onDismissRequest = { addingTrack = null }) {
            Column(Modifier.padding(24.dp)) {
                Text("Добавить в плейлист", style = MaterialTheme.typography.titleLarge)
                model.library.playlists.forEach { p ->
                    TextButton(
                        onClick = {
                            model.library.togglePlaylist(p.id, addingTrack!!)
                            addingTrack = null
                        }
                    ) {
                        Text(p.name)
                    }
                }
                TextButton(
                    onClick = {
                        newPlaylist = true
                        addingTrack = null
                    }
                ) {
                    Text("Создать плейлист")
                }
            }
        }
}

@Composable
fun <T> rememberSaveableState(initial: T): MutableState<T> =
    androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(initial) }
