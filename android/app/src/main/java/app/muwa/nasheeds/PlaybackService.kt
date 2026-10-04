package app.muwa.nasheeds

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.media3.common.*
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import kotlinx.coroutines.*
import androidx.compose.runtime.*

object AppGraph {
    lateinit var library: Library; private set
    lateinit var downloads: Downloads; private set
    lateinit var backend: Backend; private set
    fun init(context: Context) { backend = Backend(context); library = Library(context); downloads = Downloads(context, backend.mediaClient) }
    fun mediaItem(track: Track): MediaItem = MediaItem.Builder().setMediaId(track.id)
        .setUri(downloads.local(track)?.toURI()?.toString() ?: track.audio)
        .setMediaMetadata(MediaMetadata.Builder().setTitle(track.title).setArtist(track.artist).setArtworkUri(android.net.Uri.parse(track.artwork)).build()).build()
}
@androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
object SleepTimer {
    var endAt by mutableStateOf<Long?>(null); private set
    var afterTrack by mutableStateOf(false); private set
    private var player: ExoPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val stop = Runnable { player?.pause(); endAt = null; afterTrack = false }
    fun attach(player: ExoPlayer?) { this.player = player; player?.pauseAtEndOfMediaItems = afterTrack }
    fun start(minutes: Int) { cancel(); endAt = System.currentTimeMillis() + minutes * 60_000L; handler.postDelayed(stop, minutes * 60_000L) }
    fun afterCurrent() { cancel(); afterTrack = true; player?.pauseAtEndOfMediaItems = true }
    fun cancel() { handler.removeCallbacks(stop); endAt = null; afterTrack = false; player?.pauseAtEndOfMediaItems = false }
    fun finished() { if (afterTrack) { player?.pause(); cancel() } }
}
@androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
class PlaybackService : MediaSessionService() {
    private lateinit var player: ExoPlayer
    private var session: MediaSession? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    override fun onCreate() {
        super.onCreate()
        player = ExoPlayer.Builder(this).setMediaSourceFactory(DefaultMediaSourceFactory(DefaultDataSource.Factory(this, OkHttpDataSource.Factory(AppGraph.backend.mediaClient)))).build().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(), true)
            setHandleAudioBecomingNoisy(true)
        }
        SleepTimer.attach(player)
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying) currentTrack()?.let { AppGraph.library.played(it) }
            }
            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                if (!playWhenReady && reason == Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM) SleepTimer.finished()
            }
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                if (player.playWhenReady) currentTrack()?.let { AppGraph.library.played(it) }
                if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO) SleepTimer.finished()
            }
            override fun onPlaybackStateChanged(state: Int) { if (state == Player.STATE_ENDED) { AppGraph.library.resume = null; SleepTimer.finished() } }
            override fun onPlayerError(error: PlaybackException) { Diagnostics.record("playback", error) }
            override fun onTimelineChanged(timeline: Timeline, reason: Int) {
                AppGraph.library.replaceQueue((0 until player.mediaItemCount).map { player.getMediaItemAt(it).mediaId })
            }
        })
        val intent = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        session = MediaSession.Builder(this, player).setSessionActivity(intent).build()
        scope.launch {
            while (isActive) {
                delay(5000)
                val id = player.currentMediaItem?.mediaId
                if (id != null && player.currentPosition > 1000 && player.playbackState != Player.STATE_ENDED) AppGraph.library.resume = id to player.currentPosition
            }
        }
    }
    private fun currentTrack() = player.currentMediaItem?.mediaId?.let(AppGraph.library::track)
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session
    override fun onTaskRemoved(rootIntent: Intent?) { if (!player.playWhenReady || player.mediaItemCount == 0) stopSelf() }
    override fun onDestroy() { scope.cancel(); SleepTimer.cancel(); SleepTimer.attach(null); session?.release(); player.release(); super.onDestroy() }
}
