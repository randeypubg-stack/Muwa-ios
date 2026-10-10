package app.muwa.nasheeds

import android.app.Application
import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.time.Instant
import kotlinx.coroutines.*

class MuwaApplication : Application(), coil.ImageLoaderFactory {
    override fun newImageLoader() = coil.ImageLoader.Builder(this).okHttpClient(AppGraph.backend.mediaClient).build()
    override fun onCreate() {
        super.onCreate()
        Diagnostics.init(this)
        AppGraph.init(this)
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            Diagnostics.record("uncaught", error)
            previous?.uncaughtException(thread, error)
        }
    }
}
object Diagnostics {
    private lateinit var folder: File
    private var events = JSONArray()
    private var pending = JSONArray()
    private var accountId: Int? = null
    private var accountReady = false
    private lateinit var preferences: android.content.SharedPreferences
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var sending: Job? = null
    private var nextAttempt = 0L
    var remoteEnabled: Boolean
        @Synchronized get() = ::preferences.isInitialized && preferences.getBoolean("remote", false)
        @Synchronized set(value) {
            preferences.edit().putBoolean("remote", value).apply()
            if (!value) { pending = JSONArray(); persistPending(); sending?.cancel() }
            else flush()
        }
    @Synchronized fun init(context: Context) {
        folder = File(context.filesDir, "diagnostics").apply { mkdirs() }
        preferences = context.getSharedPreferences("muwa.diagnostics", Context.MODE_PRIVATE)
        val saved = runCatching { JSONObject(File(folder, "pending-remote.json").readText()) }.getOrNull()
        accountId = saved?.optInt("accountId")?.takeIf { it > 0 }
        pending = if (remoteEnabled) saved?.optJSONArray("events") ?: JSONArray() else JSONArray()
        events = runCatching { JSONArray(File(folder, "events.json").readText()) }.getOrDefault(JSONArray())
    }
    @Synchronized fun record(area: String, error: Throwable) {
        if (error is kotlinx.coroutines.CancellationException) return
        // Store class and app stack locations only, never response bodies, URLs, credentials or user input.
        val event = JSONObject().put("id", UUID.randomUUID().toString()).put("time", System.currentTimeMillis()).put("area", area).put("type", error.javaClass.name)
            .put("stack", JSONArray(error.stackTrace.filter { it.className.startsWith("app.muwa") }.take(12).map { "${it.className}.${it.methodName}:${it.lineNumber}" }))
        val retained = (maxOf(0, events.length() - 199) until events.length()).map { events.getJSONObject(it) }
        events = JSONArray(retained + event)
        if (::folder.isInitialized) runCatching { File(folder, "events.json").writeText(events.toString()) }
        Log.e("Muwa", "$area: ${error.javaClass.simpleName}")
        if (remoteEnabled && accountReady && accountId != null) {
            val allowed = setOf("auth","session","catalog","download","playback","audio-session","premium","subtitles","publication","controller","session-storage","uncaught")
            val family = when (error) { is java.io.IOException -> "network"; is androidx.media3.common.PlaybackException -> "playback"; is IllegalStateException, is IllegalArgumentException -> "state"; else -> "unknown" }
            val item = JSONObject().put("id", event.getString("id")).put("occurredAt", Instant.now().toString()).put("area", if(area in allowed) area else "other").put("errorType", family).put("errorCode", if(error is androidx.media3.common.PlaybackException) error.errorCode else if(error is ApiException) error.status else 0)
            val retainedPending = (maxOf(0, pending.length() - 199) until pending.length()).map { pending.getJSONObject(it) }
            pending = JSONArray(retainedPending + item); persistPending(); flush()
        }
    }
    @Synchronized fun setAccount(id: Int?) {
        accountReady = true
        if (accountId != id) { sending?.cancel(); sending = null; pending = JSONArray(); accountId = id; nextAttempt = 0; persistPending() }
        flush()
    }
    @Synchronized private fun persistPending() { if (::folder.isInitialized) runCatching { File(folder,"pending-remote.json").writeText(JSONObject().put("accountId",accountId ?: JSONObject.NULL).put("events",pending).toString()) } }
    @Synchronized fun flush() {
        val id = accountId ?: return
        if (!remoteEnabled || !accountReady || pending.length() == 0 || sending?.isActive == true || System.currentTimeMillis() < nextAttempt) return
        val batch = JSONArray((0 until minOf(20,pending.length())).map { JSONObject(pending.getJSONObject(it).toString()) })
        sending = scope.launch(start = CoroutineStart.LAZY) {
            try {
                AppGraph.backend.request("diagnostics/events",JSONObject().put("platform","Android").put("version",BuildConfig.VERSION_NAME).put("build",BuildConfig.VERSION_CODE.toString()).put("events",batch))
                synchronized(this@Diagnostics) {
                    if (isActive && accountId == id && remoteEnabled) {
                        val ids = (0 until batch.length()).map { batch.getJSONObject(it).getString("id") }.toSet()
                        pending = JSONArray((0 until pending.length()).map { pending.getJSONObject(it) }.filter { it.optString("id") !in ids }); persistPending(); nextAttempt = System.currentTimeMillis() + 30_000
                    }
                }
            } catch (error: Throwable) { synchronized(this@Diagnostics) { if (accountId == id) nextAttempt = System.currentTimeMillis() + if(error is ApiException && error.status == 429) 3_600_000 else 60_000 } }
        }.also { it.start() }
    }
    @Synchronized fun count() = events.length()
    @Synchronized fun export(context: Context): File = File(context.cacheDir, "reports").apply { mkdirs() }.let { dir ->
        File(dir, "Muwa-diagnostics.json").apply { writeText(JSONObject().put("platform", "Android").put("version", BuildConfig.VERSION_NAME).put("build", BuildConfig.VERSION_CODE).put("errors", events).toString(2)) }
    }
    @Synchronized fun clear() { events = JSONArray(); pending = JSONArray(); persistPending(); sending?.cancel(); if (::folder.isInitialized) File(folder, "events.json").delete() }
}
