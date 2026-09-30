package app.muwa.nasheeds

import android.app.Application
import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MuwaApplication : Application() {
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
    @Synchronized fun init(context: Context) {
        folder = File(context.filesDir, "diagnostics").apply { mkdirs() }
        events = runCatching { JSONArray(File(folder, "events.json").readText()) }.getOrDefault(JSONArray())
    }
    @Synchronized fun record(area: String, error: Throwable) {
        if (error is kotlinx.coroutines.CancellationException) return
        // Store class and app stack locations only, never response bodies, URLs, credentials or user input.
        val event = JSONObject().put("time", System.currentTimeMillis()).put("area", area).put("type", error.javaClass.name)
            .put("stack", JSONArray(error.stackTrace.filter { it.className.startsWith("app.muwa") }.take(12).map { "${it.className}.${it.methodName}:${it.lineNumber}" }))
        val retained = (maxOf(0, events.length() - 199) until events.length()).map { events.getJSONObject(it) }
        events = JSONArray(retained + event)
        if (::folder.isInitialized) runCatching { File(folder, "events.json").writeText(events.toString()) }
        Log.e("Muwa", "$area: ${error.javaClass.simpleName}")
    }
    @Synchronized fun count() = events.length()
    @Synchronized fun export(context: Context): File = File(context.cacheDir, "reports").apply { mkdirs() }.let { dir ->
        File(dir, "Muwa-diagnostics.json").apply { writeText(JSONObject().put("platform", "Android").put("version", BuildConfig.VERSION_NAME).put("build", BuildConfig.VERSION_CODE).put("errors", events).toString(2)) }
    }
    @Synchronized fun clear() { events = JSONArray(); if (::folder.isInitialized) File(folder, "events.json").delete() }
}
