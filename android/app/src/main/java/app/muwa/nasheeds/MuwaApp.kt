package app.muwa.nasheeds

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import app.muwa.nasheeds.ui.account.*
import app.muwa.nasheeds.ui.catalog.CollectionScreen
import app.muwa.nasheeds.ui.catalog.SavedTracksScreen
import app.muwa.nasheeds.ui.design.*
import app.muwa.nasheeds.ui.home.HomeScreen
import app.muwa.nasheeds.ui.library.LibraryCollectionsScreen
import app.muwa.nasheeds.ui.library.LibraryScreen
import app.muwa.nasheeds.ui.navigation.AppBottomBar
import app.muwa.nasheeds.ui.navigation.AppTopBar
import app.muwa.nasheeds.ui.player.PlayerSheet
import app.muwa.nasheeds.ui.playlists.*
import app.muwa.nasheeds.ui.profile.ProfileScreen
import app.muwa.nasheeds.ui.publication.PublicationScreen
import app.muwa.nasheeds.ui.queue.QueueScreen
import app.muwa.nasheeds.ui.search.SearchScreen
import app.muwa.nasheeds.ui.settings.SettingsScreen
import app.muwa.nasheeds.ui.state.rememberSaveableState
import app.muwa.nasheeds.ui.subtitles.SubtitleScreen

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
    var readerFromPlayer by rememberSaveableState(false)
    var playerQueue by rememberSaveableState(false)
    val topScroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
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
        if (route == "subtitles" && readerFromPlayer) {
            route = "home"
            expanded = true
            readerFromPlayer = false
        } else if (expanded) expanded = false
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
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val systemInsets = WindowInsets.systemBars.union(WindowInsets.displayCutout)
        val systemBottomDp = with(density) { systemInsets.getBottom(this).toDp().value }
        val bottomClearanceDp =
            BottomNavigationLayout.bottomClearanceDp(maxHeight.value, systemBottomDp)
        val extraBottomPadding = (bottomClearanceDp - systemBottomDp).coerceAtLeast(0f).dp
        MuwaAmbientBackground(Modifier.fillMaxSize())
        Scaffold(
            modifier = if (expanded) Modifier.clearAndSetSemantics {} else Modifier,
            containerColor = Color.Transparent,
            topBar = {
                if (!expanded)
                    AppTopBar(
                        route,
                        model,
                        topScroll,
                        { route = "search" },
                        {
                            route =
                                if (route.startsWith("collection:")) "home"
                                else if (selected == "profile") "profile" else "library"
                        },
                        {
                            route = "home"
                            expanded = readerFromPlayer
                            readerFromPlayer = false
                        },
                    )
            },
        ) { padding ->
            val chromeHeight =
                bottomClearanceDp.dp +
                    BottomNavigationLayout.barHeightDp.dp +
                    if (model.track != null && !expanded)
                        (BottomNavigationLayout.miniPlayerHeightDp +
                                BottomNavigationLayout.playerGapDp)
                            .dp
                    else 0.dp
            Box(
                Modifier.fillMaxSize()
                    .padding(padding)
                    .padding(bottom = if (route == "subtitles") 0.dp else chromeHeight)
                    .nestedScroll(topScroll.nestedScrollConnection)
            ) {
                when (route) {
                    "home" ->
                        HomeScreen(
                            model,
                            {
                                model.play(it, model.library.catalog)
                                requestNotifications()
                            },
                            { addingTrack = it },
                            { route = "collection:$it" },
                            {
                                model.resume()
                                requestNotifications()
                            },
                            openPlayer = {
                                model.play(it, model.library.catalog)
                                expanded = true
                                requestNotifications()
                            },
                        )
                    "queue" -> QueueScreen(model, play)
                    "library" -> LibraryScreen(model, { route = it }, { newPlaylist = true })
                    "playlists",
                    "publications",
                    "drafts" ->
                        LibraryCollectionsScreen(
                            model,
                            route,
                            { route = it },
                            { newPlaylist = true },
                        )
                    "profile" -> ProfileScreen(model) { route = it }
                    "search" -> SearchScreen(model, play, { addingTrack = it })
                    "favorites",
                    "history",
                    "downloads" -> SavedTracksScreen(model, route, play, { addingTrack = it })
                    "premium" -> PremiumScreen(model, { route = "promo" }, { route = "auth" })
                    "promo" -> PromoScreen(model) { route = "auth" }
                    "auth" -> AuthScreen(model)
                    "settings" -> SettingsScreen(model)
                    "subtitles" -> SubtitleScreen(model)
                    "publication" -> PublicationScreen(model)
                    else ->
                        if (route.startsWith("collection:")) {
                            CollectionScreen(
                                model,
                                route.substringAfter(':'),
                                { track, tracks ->
                                    model.play(track, tracks)
                                    requestNotifications()
                                },
                                { addingTrack = it },
                            )
                        } else if (route.startsWith("playlist:")) {
                            PlaylistScreen(
                                model,
                                route.substringAfter(':'),
                                play,
                                { addingTrack = it },
                            )
                        }
                }
            }
        }
        if (expanded && model.track != null)
            PlayerSheet(
                model,
                onClose = { expanded = false },
                onQueue = { playerQueue = true },
                onSubtitles = {
                    readerFromPlayer = true
                    model.loadSubtitles()
                    expanded = false
                    route = "subtitles"
                },
                onPlaylist = { addingTrack = model.track },
                bottomClearance = bottomClearanceDp.dp,
            )
        if (route != "subtitles")
            AppBottomBar(
                model = model,
                selected = selected,
                expanded = expanded,
                systemInsets = systemInsets,
                extraBottomPadding = extraBottomPadding,
                onNavigate = {
                    route = it
                    expanded = false
                },
                onExpandPlayer = { if (model.track != null) expanded = true },
                modifier =
                    Modifier.align(Alignment.BottomCenter)
                        .widthIn(
                            max =
                                if (minOf(maxWidth, maxHeight) >= 600.dp && maxWidth >= 700.dp)
                                    if (maxWidth > maxHeight)
                                        minOf(maxWidth, maxOf(720.dp, maxWidth * .82f))
                                    else 720.dp
                                else maxWidth
                        ),
            )
    }
    if (playerQueue)
        ModalBottomSheet(
            onDismissRequest = { playerQueue = false },
            containerColor = MuwaColors.Background,
            contentColor = MuwaColors.Text,
            dragHandle = { BottomSheetDefaults.DragHandle(color = Color.White.copy(alpha = .25f)) },
        ) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 22.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Очередь", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                TextButton(
                    onClick = { playerQueue = false },
                    modifier = Modifier.testTag("queue.close"),
                ) {
                    Text("Готово")
                }
            }
            Box(Modifier.fillMaxHeight(.9f)) {
                QueueScreen(model) {
                    play(it)
                    playerQueue = false
                }
            }
        }
    if (model.error != null)
        AlertDialog(
            onDismissRequest = { model.error = null },
            title = { Text("Не удалось выполнить действие") },
            text = { Text(model.error!!) },
            confirmButton = { TextButton(onClick = { model.error = null }) { Text("OK") } },
        )
    if (newPlaylist)
        CreatePlaylistDialog(
            name = playlistName,
            onNameChange = { playlistName = it },
            onCreate = {
                model.library.createPlaylist(playlistName)
                playlistName = ""
                newPlaylist = false
            },
            onDismiss = { newPlaylist = false },
        )
    if (addingTrack != null)
        PlaylistPickerSheet(
            model = model,
            onSelect = {
                model.library.togglePlaylist(it, addingTrack!!)
                addingTrack = null
            },
            onCreate = {
                newPlaylist = true
                addingTrack = null
            },
            onDismiss = { addingTrack = null },
        )
}
