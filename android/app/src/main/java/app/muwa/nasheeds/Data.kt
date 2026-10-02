package app.muwa.nasheeds

import android.content.Context
import androidx.compose.runtime.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class Track(val id: String, val title: String, val artist: String, val duration: Long, val artwork: String, val audio: String, val captionsRevision: Int = 0)
data class Playlist(val id: String, val name: String, val ids: List<String>)
object FeatureAccess { const val premiumRestrictionsEnabled = false; fun allowed(premium: Boolean) = !premiumRestrictionsEnabled || premium }

class Library(context: Context) {
    private val prefs = context.getSharedPreferences("muwa.library", Context.MODE_PRIVATE)
    private fun parseCatalog(rows: JSONArray): List<Track> {
        require(rows.length() <= 10000)
        val tracks = List(rows.length()) { i -> rows.getJSONObject(i).let {
            val audio = it.getString("audio").let { value -> if (value.startsWith("/")) Backend.base + value else value }
            val artwork = it.optString("artwork").takeUnless { value -> value == "null" }.orEmpty().let { value -> if (value.startsWith("/")) Backend.base + value else value }
            val duration = it.getDouble("duration")
            val id = it.getString("id")
            require(id.matches(Regex("^[A-Za-z0-9_-]{1,80}$")) && duration.isFinite() && duration > 0 && duration <= 86400 && audio.startsWith("https://") && (artwork.isEmpty() || artwork.startsWith("https://")) && it.optInt("captionsRevision",0) >= 0 && it.getString("title").isNotBlank())
            Track(id,it.getString("title"),it.getString("artist"),duration.toLong().coerceAtLeast(1),artwork,audio,it.optInt("captionsRevision",0))
        } }
        require(tracks.map { it.id }.distinct().size == tracks.size)
        return tracks
    }
    private val cached = runCatching { prefs.getString("catalog.v1",null)?.let { JSONObject(it) } }.getOrNull()
    var catalog by mutableStateOf(runCatching { cached?.getJSONArray("tracks")?.let(::parseCatalog) }.getOrNull()
        ?: parseCatalog(JSONArray(context.assets.open("catalog.json").bufferedReader().use { it.readText() }))); private set
    private val known = (runCatching { cached?.getJSONArray("known")?.let(::parseCatalog) }.getOrNull() ?: catalog).associateBy { it.id }.toMutableMap()
    fun track(id: String): Track? = known[id]
    fun updateCatalog(document: JSONObject) {
        require(document.getInt("version") == 1)
        val updated = parseCatalog(document.getJSONArray("tracks"))
        updated.forEach { known[it.id] = it }
        catalog = updated
        fun rows(tracks: Collection<Track>) = JSONArray(tracks.map { JSONObject().put("id",it.id).put("title",it.title).put("artist",it.artist).put("duration",it.duration).put("artwork",it.artwork).put("audio",it.audio).put("captionsRevision",it.captionsRevision) })
        prefs.edit().putString("catalog.v1",JSONObject().put("tracks",rows(updated)).put("known",rows(known.values)).toString()).apply()
    }
    var favorites by mutableStateOf(readIDs("favorites", emptyList()).toSet()); private set
    var history by mutableStateOf(readIDs("history", emptyList())); private set
    var queue by mutableStateOf(readIDs("queue", catalog.map { it.id })); private set
    var playlists by mutableStateOf(readPlaylists()); private set
    fun tracks(ids: Collection<String>): List<Track> = ids.mapNotNull(::track)
    private fun readIDs(key: String, fallback: List<String>): List<String> = runCatching {
        prefs.getString(key, null)?.let { JSONArray(it).let { a -> List(a.length()) { i -> a.getString(i) } } } ?: fallback
    }.getOrDefault(fallback).distinct()
    private fun saveIDs(key: String, ids: Collection<String>) { prefs.edit().putString(key, JSONArray(ids).toString()).apply() }
    private fun readPlaylists(): List<Playlist> = runCatching {
        JSONArray(prefs.getString("playlists", "[]")).let { a -> List(a.length()) { i -> a.getJSONObject(i).let { p ->
            Playlist(p.getString("id"), p.getString("name"), p.getJSONArray("ids").let { ids -> List(ids.length()) { ids.getString(it) } })
        } } }
    }.getOrDefault(emptyList())
    private fun savePlaylists() { prefs.edit().putString("playlists", JSONArray(playlists.map { JSONObject().put("id", it.id).put("name", it.name).put("ids", JSONArray(it.ids)) }).toString()).apply() }
    fun like(track: Track) { favorites = if (track.id in favorites) favorites - track.id else favorites + track.id; saveIDs("favorites", favorites) }
    fun played(track: Track) { history = (listOf(track.id) + history.filterNot { it == track.id }).take(100); saveIDs("history", history) }
    fun replaceQueue(ids: List<String>) { queue = ids.distinct().filter { id -> catalog.any { it.id == id } }; saveIDs("queue", queue) }
    fun createPlaylist(name: String): String { val id = UUID.randomUUID().toString(); playlists = playlists + Playlist(id, name.trim().ifEmpty { "Новый плейлист" }, emptyList()); savePlaylists(); return id }
    fun deletePlaylist(id: String) { playlists = playlists.filterNot { it.id == id }; savePlaylists() }
    fun renamePlaylist(id: String, name: String) { if (name.isBlank()) return; playlists = playlists.map { if (it.id == id) it.copy(name = name.trim()) else it }; savePlaylists() }
    fun togglePlaylist(id: String, track: Track) { playlists = playlists.map { if (it.id == id) it.copy(ids = if (track.id in it.ids) it.ids - track.id else it.ids + track.id) else it }; savePlaylists() }
    var resume: Pair<String, Long>?
        get() = prefs.getString("resume.id", null)?.let { it to prefs.getLong("resume.position", 0) }?.takeIf { it.second > 1000 }
        set(value) { prefs.edit().apply { if (value == null) { remove("resume.id"); remove("resume.position") } else { putString("resume.id", value.first); putLong("resume.position", value.second) } }.apply() }
}

fun formatTime(ms: Long): String { val seconds = ms.coerceAtLeast(0) / 1000; return "%d:%02d".format(seconds / 60, seconds % 60) }
