package app.muwa.nasheeds

import android.content.Context
import androidx.compose.runtime.*
import java.io.File
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request

class Downloads(context: Context, private val client: OkHttpClient) {
    companion object {
        internal const val MAXIMUM_BYTES = 100 * 1024 * 1024L
        internal val FORMATS = setOf("mp3", "m4a", "wav", "aac", "ogg")
    }

    private val prefs = context.getSharedPreferences("muwa.download.sources", Context.MODE_PRIVATE)
    private val folder = File(context.filesDir, "OfflineAudio").apply { mkdirs() }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    var downloaded by
        mutableStateOf(
            folder
                .listFiles()
                .orEmpty()
                .filter { it.extension in FORMATS && !it.name.startsWith(".") && it.length() > 0 }
                .map { it.nameWithoutExtension }
                .toSet()
        )
        private set

    init {
        val original =
            org.json.JSONArray(
                context.assets.open("catalog.json").bufferedReader().use { it.readText() }
            )
        val editor = prefs.edit()
        for (i in 0 until original.length()) {
            val row = original.getJSONObject(i)
            val id = row.getString("id")
            if (id in downloaded && !prefs.contains(id))
                editor.putString(id, row.getString("audio"))
        }
        editor.apply()
    }

    val progress = mutableStateMapOf<String, Float>()
    private val jobs = mutableMapOf<String, Job>()

    private fun destination(
        track: Track,
        extension: String =
            prefs.getString("format:${track.id}", "mp3").takeIf { it in FORMATS } ?: "mp3",
    ) = File(folder, "${track.id}.$extension")

    fun local(track: Track): File? =
        destination(track).takeIf {
            track.id in downloaded && it.exists() && prefs.getString(track.id, null) == track.audio
        }

    fun bytes(): Long =
        folder
            .listFiles()
            .orEmpty()
            .filter { it.extension in FORMATS && !it.name.startsWith(".") }
            .sumOf { it.length() }

    fun cancel(track: Track) {
        jobs[track.id]?.cancel()
    }

    fun remove(track: Track) {
        if (jobs.containsKey(track.id)) {
            cancel(track)
            return
        }
        check(destination(track).let { !it.exists() || it.delete() }) { "Не удалось удалить файл." }
        downloaded = downloaded - track.id
        prefs.edit().remove(track.id).remove("format:${track.id}").apply()
    }

    fun download(track: Track, onError: (Throwable) -> Unit) {
        if (local(track) != null || jobs.containsKey(track.id)) return
        if (jobs.size >= 3) {
            onError(IllegalStateException("Дождитесь завершения текущих загрузок."))
            return
        }
        progress[track.id] = 0f
        jobs[track.id] =
            scope.launch {
                val partial = File(folder, ".${track.id}.part")
                var extension = "mp3"
                var staged: File? = null
                try {
                    val owner = currentCoroutineContext()[Job]
                    withContext(Dispatchers.IO) {
                        val downloadContext = currentCoroutineContext()
                        val call = client.newCall(Request.Builder().url(track.audio).build())
                        try {
                            call.awaitResult { response ->
                                check(response.isSuccessful) {
                                    "Не удалось скачать (${response.code})."
                                }
                                val mime = response.header("Content-Type").orEmpty()
                                check(!mime.contains("html") && !mime.contains("json")) {
                                    "Сервер вернул файл неверного формата."
                                }
                                val body = requireNotNull(response.body)
                                transferAudio(
                                    body,
                                    partial,
                                    checkActive = { downloadContext.ensureActive() },
                                ) { value ->
                                    scope.launch {
                                        if (jobs[track.id] === owner && owner?.isActive == true)
                                            progress[track.id] = value
                                    }
                                }
                                extension =
                                    audioContainer(
                                        partial.inputStream().use { input ->
                                            ByteArray(16).also { bytes ->
                                                java.io.DataInputStream(input).readFully(bytes)
                                            }
                                        }
                                    )
                                val typed = File(folder, ".${track.id}.part.$extension")
                                staged = typed
                                check(partial.renameTo(typed)) { "Не удалось подготовить аудио." }
                                val metadata = android.media.MediaMetadataRetriever()
                                try {
                                    metadata.setDataSource(requireNotNull(staged).absolutePath)
                                    check(
                                        metadata.extractMetadata(
                                            android.media.MediaMetadataRetriever
                                                .METADATA_KEY_HAS_AUDIO
                                        ) == "yes"
                                    ) {
                                        "Файл не содержит аудио."
                                    }
                                } finally {
                                    metadata.release()
                                }
                            }
                            ensureActive()
                            check(requireNotNull(staged).renameTo(destination(track, extension))) {
                                "Не удалось сохранить файл."
                            }
                        } finally {
                            call.cancel()
                        }
                    }
                    prefs
                        .edit()
                        .putString(track.id, track.audio)
                        .putString("format:${track.id}", extension)
                        .apply()
                    downloaded = downloaded + track.id
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    Diagnostics.record("download", e)
                    onError(e)
                } finally {
                    partial.delete()
                    staged?.delete()
                    progress.remove(track.id)
                    jobs.remove(track.id)
                }
            }
    }
}

// Bounded streaming keeps cancellation active while the body is read. The caller
// owns temporary-file cleanup and only publishes media after decoder validation.
internal fun transferAudio(
    body: okhttp3.ResponseBody,
    partial: File,
    maximumBytes: Long = Downloads.MAXIMUM_BYTES,
    checkActive: () -> Unit = {},
    onProgress: (Float) -> Unit = {},
) {
    val total = body.contentLength()
    val reserve = 64 * 1024 * 1024L
    check(total <= maximumBytes && partial.parentFile!!.usableSpace >= maxOf(total, 0) + reserve) {
        "Файл слишком большой или недостаточно места."
    }
    var done = 0L
    var last = 0L
    partial.outputStream().use { out ->
        body.byteStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                checkActive()
                val count = input.read(buffer)
                if (count < 0) break
                check(
                    done + count <= maximumBytes &&
                        partial.parentFile!!.usableSpace > count + reserve
                ) {
                    "Превышен размер файла или недостаточно места."
                }
                out.write(buffer, 0, count)
                done += count
                if (System.currentTimeMillis() - last > 200) {
                    last = System.currentTimeMillis()
                    onProgress(if (total > 0) (done.toFloat() / total).coerceIn(0f, 1f) else 0f)
                }
            }
        }
    }
    check(done > 0 && (total < 0 || done == total)) { "Файл пуст или загружен не полностью." }
}

// Signed catalogue links have no container suffix. Persist the actual format
// so Media3 sees the same playable container after an offline restart.
internal fun audioContainer(header: ByteArray): String {
    fun at(offset: Int, text: String) =
        header.size >= offset + text.length &&
            header
                .copyOfRange(offset, offset + text.length)
                .contentEquals(text.toByteArray(Charsets.US_ASCII))
    return when {
        at(0, "ID3") -> "mp3"
        at(0, "RIFF") && at(8, "WAVE") -> "wav"
        at(4, "ftyp") -> "m4a"
        at(0, "OggS") -> "ogg"
        header.size >= 2 &&
            (header[0].toInt() and 255) == 255 &&
            (header[1].toInt() and 224) == 224 ->
            if ((header[1].toInt() and 6) == 0) "aac" else "mp3"
        else -> error("Файл не содержит поддерживаемое аудио.")
    }
}
