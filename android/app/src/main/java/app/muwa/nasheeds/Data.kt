package app.muwa.nasheeds

import android.content.Context
import androidx.compose.runtime.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class Track(val id: String, val title: String, val artist: String, val duration: Long, val artwork: String, val audio: String)
data class Playlist(val id: String, val name: String, val ids: List<String>)
object FeatureAccess { const val premiumRestrictionsEnabled = false; fun allowed(premium: Boolean) = !premiumRestrictionsEnabled || premium }

class Library(private val context: Context) {
    private val prefs = context.getSharedPreferences("muwa.library", Context.MODE_PRIVATE)
    val catalog: List<Track> = JSONArray(context.assets.open("catalog.json").bufferedReader().use { it.readText() }).let { rows ->
        List(rows.length()) { i -> rows.getJSONObject(i).let { Track(it.getString("id"), it.getString("title"), it.getString("artist"), it.getLong("duration"), it.getString("artwork"), it.getString("audio")) } }
    }
    var favorites by mutableStateOf(readIDs("favorites", emptyList()).toSet()); private set
    var history by mutableStateOf(readIDs("history", emptyList())); private set
    var queue by mutableStateOf(readIDs("queue", catalog.map { it.id })); private set
    var playlists by mutableStateOf(readPlaylists()); private set
    fun tracks(ids: Collection<String>): List<Track> = ids.mapNotNull { id -> catalog.firstOrNull { it.id == id } }
    private fun readIDs(key: String, fallback: List<String>): List<String> = runCatching {
        prefs.getString(key, null)?.let { JSONArray(it).let { a -> List(a.length()) { i -> a.getString(i) } } } ?: fallback
    }.getOrDefault(fallback).filter { id -> catalog.any { it.id == id } }.distinct()
    private fun saveIDs(key: String, ids: Collection<String>) { prefs.edit().putString(key, JSONArray(ids).toString()).apply() }
    private fun readPlaylists(): List<Playlist> = runCatching {
        JSONArray(prefs.getString("playlists", "[]")).let { a -> List(a.length()) { i -> a.getJSONObject(i).let { p ->
            Playlist(p.getString("id"), p.getString("name"), p.getJSONArray("ids").let { ids -> List(ids.length()) { ids.getString(it) } })
        } } }
    }.getOrDefault(emptyList())
    private fun savePlaylists() { prefs.edit().putString("playlists", JSONArray(playlists.map { JSONObject().put("id", it.id).put("name", it.name).put("ids", JSONArray(it.ids)) }).toString()).apply() }
    fun like(track: Track) { favorites = if (track.id in favorites) favorites - track.id else favorites + track.id; saveIDs("favorites", favorites) }
    fun played(track: Track) { history = (listOf(track.id) + history.filterNot { it == track.id }).take(100); saveIDs("history", history) }
    fun setQueue(ids: List<String>) { queue = ids.distinct().filter { id -> catalog.any { it.id == id } }; saveIDs("queue", queue) }
    fun createPlaylist(name: String): String { val id = UUID.randomUUID().toString(); playlists = playlists + Playlist(id, name.trim().ifEmpty { "Новый плейлист" }, emptyList()); savePlaylists(); return id }
    fun deletePlaylist(id: String) { playlists = playlists.filterNot { it.id == id }; savePlaylists() }
    fun renamePlaylist(id: String, name: String) { if (name.isBlank()) return; playlists = playlists.map { if (it.id == id) it.copy(name = name.trim()) else it }; savePlaylists() }
    fun togglePlaylist(id: String, track: Track) { playlists = playlists.map { if (it.id == id) it.copy(ids = if (track.id in it.ids) it.ids - track.id else it.ids + track.id) else it }; savePlaylists() }
    var resume: Pair<String, Long>?
        get() = prefs.getString("resume.id", null)?.let { it to prefs.getLong("resume.position", 0) }?.takeIf { it.second > 1000 }
        set(value) { prefs.edit().apply { if (value == null) { remove("resume.id"); remove("resume.position") } else { putString("resume.id", value.first); putLong("resume.position", value.second) } }.apply() }
}

fun formatTime(ms: Long): String { val seconds = ms.coerceAtLeast(0) / 1000; return "%d:%02d".format(seconds / 60, seconds % 60) }
