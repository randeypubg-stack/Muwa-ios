package app.muwa.nasheeds

import android.content.Context
import androidx.compose.runtime.*
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File

class Downloads(context: Context, private val client: OkHttpClient) {
    companion object { internal const val MAXIMUM_BYTES = 100 * 1024 * 1024L }
    private val prefs = context.getSharedPreferences("muwa.download.sources", Context.MODE_PRIVATE)
    private val folder = File(context.filesDir, "OfflineAudio").apply { mkdirs() }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    var downloaded by mutableStateOf(folder.listFiles().orEmpty().filter { it.extension == "mp3" && it.length() > 0 }.map { it.nameWithoutExtension }.toSet()); private set
    init {
        val original = org.json.JSONArray(context.assets.open("catalog.json").bufferedReader().use { it.readText() })
        val editor = prefs.edit()
        for (i in 0 until original.length()) {
            val row = original.getJSONObject(i); val id = row.getString("id")
            if (id in downloaded && !prefs.contains(id)) editor.putString(id,row.getString("audio"))
        }
        editor.apply()
    }
    val progress = mutableStateMapOf<String, Float>()
    private val jobs = mutableMapOf<String, Job>()
    fun local(track: Track): File? = File(folder, "${track.id}.mp3").takeIf { track.id in downloaded && it.exists() && prefs.getString(track.id,null) == track.audio }
    fun bytes(): Long = folder.listFiles().orEmpty().filter { it.extension == "mp3" }.sumOf { it.length() }
    fun cancel(track: Track) { jobs[track.id]?.cancel() }
    fun remove(track: Track) { if (jobs.containsKey(track.id)) { cancel(track); return }; check(File(folder, "${track.id}.mp3").let { !it.exists() || it.delete() }) { "Не удалось удалить файл." }; downloaded = downloaded - track.id; prefs.edit().remove(track.id).apply() }
    fun download(track: Track, onError: (Throwable) -> Unit) {
        if (local(track) != null || jobs.containsKey(track.id)) return
        if (jobs.size >= 3) { onError(IllegalStateException("Дождитесь завершения текущих загрузок.")); return }
        progress[track.id] = 0f
        jobs[track.id] = scope.launch {
            val partial = File(folder, "${track.id}.part")
            try {
                val owner = currentCoroutineContext()[Job]
                withContext(Dispatchers.IO) {
                    val downloadContext = currentCoroutineContext()
                    val call = client.newCall(Request.Builder().url(track.audio).build())
                    try {
                        call.awaitResult { response ->
                            check(response.isSuccessful) { "Не удалось скачать (${response.code})." }
                            val mime = response.header("Content-Type").orEmpty()
                            check(!mime.contains("html") && !mime.contains("json")) { "Сервер вернул файл неверного формата." }
                            val body = requireNotNull(response.body)
                            transferAudio(body, partial, checkActive = { downloadContext.ensureActive() }) { value ->
                                scope.launch { if (jobs[track.id] === owner && owner?.isActive == true) progress[track.id] = value }
                            }
                            val metadata = android.media.MediaMetadataRetriever()
                            try {
                                metadata.setDataSource(partial.absolutePath)
                                check(metadata.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes") { "Файл не содержит аудио." }
                            } finally { metadata.release() }
                        }
                        ensureActive()
                        check(partial.renameTo(File(folder, "${track.id}.mp3"))) { "Не удалось сохранить файл." }
                    } finally { call.cancel() }
                }
                prefs.edit().putString(track.id,track.audio).apply()
                downloaded = downloaded + track.id
            } catch (e: CancellationException) { throw e }
            catch (e: Throwable) { Diagnostics.record("download", e); onError(e) }
            finally { partial.delete(); progress.remove(track.id); jobs.remove(track.id) }
        }
    }
}

// Bounded streaming keeps cancellation active while the body is read. The caller
// owns temporary-file cleanup and only publishes media after decoder validation.
internal fun transferAudio(body: okhttp3.ResponseBody, partial: File,
                           maximumBytes: Long = Downloads.MAXIMUM_BYTES,
                           checkActive: () -> Unit = {}, onProgress: (Float) -> Unit = {}) {
    val total = body.contentLength()
    val reserve = 64 * 1024 * 1024L
    check(total <= maximumBytes && partial.parentFile!!.usableSpace >= maxOf(total, 0) + reserve) { "Файл слишком большой или недостаточно места." }
    var done = 0L
    var last = 0L
    partial.outputStream().use { out -> body.byteStream().use { input ->
        val buffer = ByteArray(64 * 1024)
        while (true) {
            checkActive()
            val count = input.read(buffer)
            if (count < 0) break
            check(done + count <= maximumBytes && partial.parentFile!!.usableSpace > count + reserve) { "Превышен размер файла или недостаточно места." }
            out.write(buffer, 0, count)
            done += count
            if (System.currentTimeMillis() - last > 200) {
                last = System.currentTimeMillis()
                onProgress(if (total > 0) (done.toFloat() / total).coerceIn(0f, 1f) else 0f)
            }
        }
    } }
    check(done > 0 && (total < 0 || done == total)) { "Файл пуст или загружен не полностью." }
}
