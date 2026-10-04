package app.muwa.nasheeds

import android.app.Application
import android.content.ComponentName
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONArray

class MuwaModel(application: Application) : AndroidViewModel(application) {
    val library = AppGraph.library
    val downloads = AppGraph.downloads
    private val backend = AppGraph.backend
    var controller by mutableStateOf<MediaController?>(null); private set
    var track by mutableStateOf<Track?>(null); private set
    var playing by mutableStateOf(false); private set
    var buffering by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null)
    var position by mutableLongStateOf(0); private set
    var duration by mutableLongStateOf(0); private set
    var shuffle by mutableStateOf(false); private set
    var repeat by mutableIntStateOf(Player.REPEAT_MODE_OFF); private set
    var user by mutableStateOf<JSONObject?>(null); private set
    var premium by mutableStateOf<JSONObject?>(null); private set
    var busy by mutableStateOf(false); private set
    var message by mutableStateOf<String?>(null); private set
    var codes by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var createdCode by mutableStateOf<String?>(null); private set
    var subtitles by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var subtitleStatus by mutableStateOf("Текст ещё не загружен"); private set
    var subtitleLoading by mutableStateOf(false); private set
    var resumeCandidate by mutableStateOf(library.resume); private set
    private var accountRevision = 0
    private var subtitleJob: Job? = null
    private var subtitleRevision = 0
    private var sessionRestoreJob: Job? = null
    private var catalogJob: Job? = null
    private var lastCatalogRefresh = 0L
    private val future = MediaController.Builder(application, SessionToken(application, ComponentName(application, PlaybackService::class.java))).buildAsync()
    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) { updatePlayer() }
        override fun onPlayerError(error: PlaybackException) { this@MuwaModel.error = "Не удалось воспроизвести. Проверьте сеть и нажмите повтор." }
    }
    init {
        refreshCatalog()
        future.addListener({ runCatching {
            controller = future.get(); controller?.addListener(listener); updatePlayer()
        }.onFailure { report("controller", it) } }, ContextCompat.getMainExecutor(application))
        viewModelScope.launch {
            while (isActive) { delay(350); controller?.let { position = it.currentPosition.coerceAtLeast(0); duration = if (it.duration > 0) it.duration else (track?.duration ?: 0) * 1000 } }
        }
        sessionRestoreJob = viewModelScope.launch {
            val revision = accountRevision
            try {
                val restored = backend.request("auth/session").optJSONObject("user")
                if (revision == accountRevision) { user = restored; Diagnostics.setAccount(restored?.optInt("id")); refreshPremium() }
            }
            catch (e: CancellationException) { throw e }
            catch (e: ApiException) { if (revision == accountRevision && e.status == 401) Diagnostics.setAccount(null); if (revision == accountRevision && e.status != 401) report("session", e) }
            catch (e: Throwable) { if (revision == accountRevision) report("session", e) }
        }
    }
    private fun updatePlayer() { controller?.let { p ->
        val new = p.currentMediaItem?.mediaId?.let { id -> track?.takeIf { it.id == id } ?: library.track(id) }
        if (new?.id != track?.id) {
            subtitleRevision++; subtitleJob?.cancel(); subtitleLoading = false
            subtitles = emptyList(); subtitleStatus = "Текст ещё не загружен"
        }
        track = new; playing = p.isPlaying; buffering = p.playbackState == Player.STATE_BUFFERING; shuffle = p.shuffleModeEnabled; repeat = p.repeatMode
    } }
    fun play(track: Track, autoplay: Boolean = true) {
        val p = controller ?: run { error = "Плеер ещё подключается. Попробуйте через секунду."; return }
        val queue = if (track.id in library.queue) library.queue else library.queue + track.id
        library.replaceQueue(queue)
        val playable = library.tracks(queue)
        if (this.track?.id != track.id || this.track?.audio != track.audio) {
            subtitleRevision++; subtitleJob?.cancel(); subtitles = emptyList(); subtitleLoading = false; subtitleStatus = "Текст ещё не загружен"
        }
        this.track = track
        p.setMediaItems(playable.map(AppGraph::mediaItem), playable.indexOfFirst { it.id == track.id }, 0)
        p.prepare(); p.playWhenReady = autoplay
        if (autoplay) library.played(track)
        resumeCandidate = null; error = null
    }
    fun toggle() { controller?.let { if (it.isPlaying) it.pause() else { if (it.playerError != null) it.prepare(); it.play() } } }
    fun retry() { controller?.prepare(); controller?.play(); error = null }
    fun next() { controller?.seekToNextMediaItem() }
    fun previous() { controller?.let { if (it.currentPosition > 4000) it.seekTo(0) else it.seekToPreviousMediaItem() } }
    fun seek(ms: Long) { controller?.seekTo(ms.coerceIn(0, duration.coerceAtLeast(0))) }
    fun toggleShuffle() { controller?.let { it.shuffleModeEnabled = !it.shuffleModeEnabled } }
    fun cycleRepeat() { controller?.let { it.repeatMode = when(it.repeatMode) { Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL; Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE; else -> Player.REPEAT_MODE_OFF } } }
    fun refreshCatalog() {
        if (catalogJob?.isActive == true || System.currentTimeMillis() - lastCatalogRefresh < 30_000) return
        catalogJob = viewModelScope.launch {
            try { library.updateCatalog(backend.request("catalog/tracks")); lastCatalogRefresh = System.currentTimeMillis() }
            catch (e: CancellationException) { throw e }
            catch (e: Throwable) { Diagnostics.record("catalog",e) }
        }
    }
    fun resume() { val value = resumeCandidate ?: return; library.track(value.first)?.let { play(it); controller?.seekTo(value.second) } }
    fun dismissResume() { resumeCandidate = null; library.resume = null }
    fun addQueue(track: Track, next: Boolean = false) {
        val p = controller
        if (p == null || p.mediaItemCount == 0) { library.replaceQueue(library.queue + track.id); return }
        val existing = (0 until p.mediaItemCount).firstOrNull { p.getMediaItemAt(it).mediaId == track.id }
        val target = if (next) (p.currentMediaItemIndex + 1).coerceAtMost(p.mediaItemCount) else p.mediaItemCount
        if (existing == null) p.addMediaItem(target, AppGraph.mediaItem(track))
        else if (next && existing != p.currentMediaItemIndex) p.moveMediaItem(existing, (if(existing < target) target - 1 else target).coerceAtMost(p.mediaItemCount - 1))
    }
    fun removeQueue(id: String) { controller?.let { p -> val index = (0 until p.mediaItemCount).firstOrNull { p.getMediaItemAt(it).mediaId == id }; if (index != null) p.removeMediaItem(index) }; library.replaceQueue(library.queue - id) }
    fun moveQueue(id: String, delta: Int) {
        val ids = library.queue.toMutableList(); val from = ids.indexOf(id); val to = from + delta
        if (from < 0 || to !in ids.indices) return
        ids.add(to, ids.removeAt(from)); library.replaceQueue(ids)
        controller?.let { if (it.mediaItemCount == ids.size) it.moveMediaItem(from, to) }
    }
    private fun report(area: String, e: Throwable) { if (e is CancellationException) return; Diagnostics.record(area,e); error = e.message ?: "Не удалось выполнить действие." }
    private fun action(area: String, operation: suspend () -> Unit) {
        if (busy) return
        busy = true; error = null; message = null
        viewModelScope.launch { try { operation() } catch(e: CancellationException) { throw e } catch(e: Throwable) { report(area,e) } finally { busy = false } }
    }
    fun login(email: String, password: String, name: String? = null) = action("auth") {
        accountRevision++; sessionRestoreJob?.cancel()
        val body = JSONObject().put("email",email.trim().lowercase()).put("password",password)
        if (name != null) body.put("displayName",name.trim())
        val result = backend.request(if(name == null) "auth/login_with_password" else "auth/register_with_password",body,true)
        user = result.getJSONObject("user"); Diagnostics.setAccount(user?.optInt("id")); premium = null; codes = emptyList(); createdCode = null
        message = "Вы вошли в Muwa."
        refreshCatalog()
        try { refreshPremium() }
        catch (e: CancellationException) { throw e }
        catch (e: Throwable) { Diagnostics.record("premium", e); message = "Вы вошли в Muwa. Статус Premium временно недоступен." }
    }
    fun logout() = action("logout") {
        accountRevision++; sessionRestoreJob?.cancel(); user = null; Diagnostics.setAccount(null); premium = null; codes = emptyList(); createdCode = null
        try { backend.request("auth/logout",JSONObject(),true) } finally { backend.clearSession() }
    }
    suspend fun refreshPremium() {
        if (user == null) return
        val revision = accountRevision; val id = user?.optInt("id")
        val value = backend.request("premium/access",JSONObject().put("action","status"))
        if (revision == accountRevision && id == value.optInt("userId")) premium = value
    }
    fun premiumAction(body: JSONObject) = action("premium") {
        check(user != null) { "Войдите в аккаунт Muwa." }
        val revision = accountRevision; val id = user?.optInt("id")
        val result = backend.request("premium/access",body)
        if (revision != accountRevision || id != result.optInt("userId")) return@action
        premium = result
        result.optJSONArray("codes")?.let { rows -> codes = List(rows.length()) { rows.getJSONObject(it) } }
        if (result.has("code")) createdCode = result.getString("code")
        message = when(body.optString("action")) {
            "redeem" -> if (result.optBoolean("alreadyRedeemed")) "Этот код уже активирован." else "Premium активирован."
            "disable" -> "Код отключён. Выданный доступ сохранён."
            "create" -> "Код создан. Сохраните его перед закрытием."
            else -> "Статус обновлён."
        }
    }
    fun savedCode() { createdCode = null }
    fun loadSubtitles() {
        val t = track ?: return
        val revision = ++subtitleRevision
        subtitleJob?.cancel()
        subtitleJob = viewModelScope.launch {
            subtitleLoading = true; subtitleStatus = "Загружаем текст…"
            try {
                val cache = java.io.File(getApplication<Application>().cacheDir,if (t.captionsRevision > 0) "subtitles-${t.id}-r${t.captionsRevision}.json" else "subtitles-${t.id}.json")
                val result = withContext(Dispatchers.IO) {
                    if (cache.exists()) JSONObject(cache.readText()) else {
                        val published = try { backend.request("catalog/captions?trackId=${t.id}") }
                        catch (e: CancellationException) { throw e }
                        catch (e: Throwable) { if (t.captionsRevision > 0) throw e else null }
                        val path = android.net.Uri.parse(t.audio).path.orEmpty()
                        val result = if (t.captionsRevision > 0 || (published?.optJSONArray("segments")?.length() ?: 0) > 0 || !path.startsWith("/_cdn/static/")) published ?: JSONObject().put("segments",JSONArray())
                        else backend.request("transcribe", JSONObject().put("src",path).put("title",t.title).put("durationSeconds",t.duration),true)
                        cache.writeText(result.toString()); result
                    }
                }
                if (subtitleRevision != revision || track?.id != t.id) return@launch
                val values = result.optJSONArray("segments") ?: JSONArray()
                subtitles = List(values.length()) { values.getJSONObject(it) }
                subtitleStatus = if (subtitles.isEmpty()) "Для этого нашида готового текста пока нет." else "Субтитры доступны бесплатно."
            } catch(e: CancellationException) { throw e }
            catch(e: Throwable) {
                if (subtitleRevision == revision && track?.id == t.id) {
                    Diagnostics.record("subtitles", e); subtitleStatus = "Готовый текст недоступен. Автоматическое распознавание пока приостановлено."
                }
            }
            finally { if (subtitleRevision == revision) subtitleLoading = false }
        }
    }
    override fun onCleared() { controller?.removeListener(listener); MediaController.releaseFuture(future); super.onCleared() }
}
