package app.muwa.nasheeds

import android.content.Context
import androidx.compose.runtime.*
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

class Downloads(context: Context) {
    private val folder = File(context.filesDir, "OfflineAudio").apply { mkdirs() }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val client = OkHttpClient.Builder().readTimeout(60, TimeUnit.SECONDS).build()
    var downloaded by mutableStateOf(folder.listFiles().orEmpty().filter { it.extension == "mp3" && it.length() > 0 }.map { it.nameWithoutExtension }.toSet()); private set
    val progress = mutableStateMapOf<String, Float>()
    private val jobs = mutableMapOf<String, Job>()
    fun local(track: Track): File? = File(folder, "${track.id}.mp3").takeIf { track.id in downloaded && it.exists() }
    fun bytes(): Long = folder.listFiles().orEmpty().filter { it.extension == "mp3" }.sumOf { it.length() }
    fun cancel(track: Track) { jobs[track.id]?.cancel() }
    fun remove(track: Track) { if (jobs.containsKey(track.id)) { cancel(track); return }; check(File(folder, "${track.id}.mp3").let { !it.exists() || it.delete() }) { "Не удалось удалить файл." }; downloaded = downloaded - track.id }
    fun download(track: Track, onError: (Throwable) -> Unit) {
        if (local(track) != null || jobs.containsKey(track.id)) return
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
                            val body = requireNotNull(response.body); val total = body.contentLength(); var done = 0L; var last = 0L
                            partial.outputStream().use { out -> body.byteStream().use { input ->
                                val buffer = ByteArray(64 * 1024)
                                while (true) {
                                    downloadContext.ensureActive(); val count = input.read(buffer); if (count < 0) break
                                    out.write(buffer, 0, count); done += count
                                    if (System.currentTimeMillis() - last > 200) {
                                        last = System.currentTimeMillis()
                                        val value = if (total > 0) (done.toFloat() / total).coerceIn(0f,1f) else 0f
                                        scope.launch { if (jobs[track.id] === owner && owner?.isActive == true) progress[track.id] = value }
                                    }
                                }
                            } }
                            check(done > 0) { "Скачан пустой файл." }
                        }
                        ensureActive()
                        check(partial.renameTo(File(folder, "${track.id}.mp3"))) { "Не удалось сохранить файл." }
                    } finally { call.cancel() }
                }
                downloaded = downloaded + track.id
            } catch (e: CancellationException) { throw e }
            catch (e: Throwable) { Diagnostics.record("download", e); onError(e) }
            finally { partial.delete(); progress.remove(track.id); jobs.remove(track.id) }
        }
    }
}
