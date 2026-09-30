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
    private val future = MediaController.Builder(application, SessionToken(application, ComponentName(application, PlaybackService::class.java))).buildAsync()
    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) { updatePlayer() }
        override fun onPlayerError(error: PlaybackException) { this@MuwaModel.error = "Не удалось воспроизвести. Проверьте сеть и нажмите повтор." }
    }
    init {
        future.addListener({ runCatching {
            controller = future.get(); controller?.addListener(listener); updatePlayer()
        }.onFailure { report("controller", it) } }, ContextCompat.getMainExecutor(application))
        viewModelScope.launch {
            while (isActive) { delay(350); controller?.let { position = it.currentPosition.coerceAtLeast(0); duration = if (it.duration > 0) it.duration else (track?.duration ?: 0) * 1000 } }
        }
        viewModelScope.launch {
            try { user = backend.request("auth/session").optJSONObject("user"); refreshPremium() }
            catch (e: ApiException) { if (e.status != 401) report("session", e) }
            catch (e: Throwable) { report("session", e) }
        }
    }
    private fun updatePlayer() { controller?.let { p ->
        val new = library.catalog.firstOrNull { it.id == p.currentMediaItem?.mediaId }
        if (new?.id != track?.id) { subtitleJob?.cancel(); subtitles = emptyList(); subtitleStatus = "Текст ещё не загружен" }
        track = new; playing = p.isPlaying; buffering = p.playbackState == Player.STATE_BUFFERING; shuffle = p.shuffleModeEnabled; repeat = p.repeatMode
    } }
    fun play(track: Track, autoplay: Boolean = true) {
        val p = controller ?: run { error = "Плеер ещё подключается. Попробуйте через секунду."; return }
        val queue = if (track.id in library.queue) library.queue else library.queue + track.id
        library.setQueue(queue)
        p.setMediaItems(library.tracks(queue).map(AppGraph::mediaItem), queue.indexOf(track.id), 0)
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
    fun resume() { val value = resumeCandidate ?: return; library.catalog.firstOrNull { it.id == value.first }?.let { play(it); controller?.seekTo(value.second) } }
    fun dismissResume() { resumeCandidate = null; library.resume = null }
    fun addQueue(track: Track, next: Boolean = false) {
        val p = controller
        if (p == null || p.mediaItemCount == 0) { library.setQueue(library.queue + track.id); return }
        val existing = (0 until p.mediaItemCount).firstOrNull { p.getMediaItemAt(it).mediaId == track.id }
        val target = if (next) (p.currentMediaItemIndex + 1).coerceAtMost(p.mediaItemCount) else p.mediaItemCount
        if (existing == null) p.addMediaItem(target, AppGraph.mediaItem(track))
        else if (next && existing != p.currentMediaItemIndex) p.moveMediaItem(existing, (if(existing < target) target - 1 else target).coerceAtMost(p.mediaItemCount - 1))
    }
    fun removeQueue(id: String) { controller?.let { p -> val index = (0 until p.mediaItemCount).firstOrNull { p.getMediaItemAt(it).mediaId == id }; if (index != null) p.removeMediaItem(index) }; library.setQueue(library.queue - id) }
    fun moveQueue(id: String, delta: Int) {
        val ids = library.queue.toMutableList(); val from = ids.indexOf(id); val to = from + delta
        if (from < 0 || to !in ids.indices) return
        ids.add(to, ids.removeAt(from)); library.setQueue(ids)
        controller?.let { if (it.mediaItemCount == ids.size) it.moveMediaItem(from, to) }
    }
    private fun report(area: String, e: Throwable) { if (e is CancellationException) return; Diagnostics.record(area,e); error = e.message ?: "Не удалось выполнить действие." }
    private fun action(area: String, operation: suspend () -> Unit) {
        if (busy) return
        busy = true; error = null; message = null
        viewModelScope.launch { try { operation() } catch(e: CancellationException) { throw e } catch(e: Throwable) { report(area,e) } finally { busy = false } }
    }
    fun login(email: String, password: String, name: String? = null) = action("auth") {
        val body = JSONObject().put("email",email.trim().lowercase()).put("password",password)
        if (name != null) body.put("displayName",name.trim())
        val result = backend.request(if(name == null) "auth/login_with_password" else "auth/register_with_password",body,true)
        accountRevision++; user = result.getJSONObject("user"); premium = null; refreshPremium(); message = "Вы вошли в Muwa."
    }
    fun logout() = action("logout") {
        accountRevision++; user = null; premium = null; codes = emptyList(); createdCode = null
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
        subtitleJob?.cancel()
        subtitleJob = viewModelScope.launch {
            subtitleLoading = true; subtitleStatus = "Загружаем текст…"
            try {
                val cache = java.io.File(getApplication<Application>().cacheDir,"subtitles-${t.id}.json")
                val result = withContext(Dispatchers.IO) {
                    if (cache.exists()) JSONObject(cache.readText()) else backend.request("transcribe", JSONObject().put("src",android.net.Uri.parse(t.audio).path).put("title",t.title).put("durationSeconds",t.duration),true).also { cache.writeText(it.toString()) }
                }
                if (track?.id != t.id) return@launch
                val values = result.optJSONArray("segments") ?: JSONArray()
                subtitles = List(values.length()) { values.getJSONObject(it) }
                subtitleStatus = if (subtitles.isEmpty()) "Для этого нашида готового текста пока нет." else "Субтитры доступны бесплатно."
            } catch(e: CancellationException) { throw e }
            catch(e: Throwable) { Diagnostics.record("subtitles", e); subtitleStatus = "Готовый текст недоступен. Автоматическое распознавание пока приостановлено." }
            finally { subtitleLoading = false }
        }
    }
    override fun onCleared() { controller?.removeListener(listener); MediaController.releaseFuture(future); super.onCleared() }
}
