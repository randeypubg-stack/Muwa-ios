package app.muwa.nasheeds

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.muwa.nasheeds.ui.design.MuwaTheme
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : ComponentActivity() {
    companion object {
        private var launchHasPlayed = false
    }

    private var systemLaunchReady by mutableStateOf(Build.VERSION.SDK_INT < 31)
    private val notifications =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        if (Build.VERSION.SDK_INT >= 31) {
            splashScreen.setOnExitAnimationListener { splash ->
                splash.remove()
                systemLaunchReady = true
            }
        }
        val reviewRoute = if (BuildConfig.DEBUG) intent.getStringExtra("review.route") else null
        // Explicit debug review routes need data even after instrumentation
        // uninstalls its target APK. The fixture asset is absent from release.
        if (reviewRoute != null && AppGraph.library.catalog.isEmpty()) {
            val rows =
                JSONArray(assets.open("review-catalog.json").bufferedReader().use { it.readText() })
            AppGraph.library.updateCatalog(JSONObject().put("version", 1).put("tracks", rows))
            AppGraph.library.replaceQueue(AppGraph.library.catalog.map { it.id })
        }
        AppGraph.reviewPlaybackEnabled = BuildConfig.DEBUG && reviewRoute != null
        // A cold process can receive a saved Activity bundle from Recents. Process
        // ownership, rather than bundle presence, decides whether launch has played.
        val showIntro = (reviewRoute == null || reviewRoute == "launch") && !launchHasPlayed
        launchHasPlayed = true
        setContent {
            MuwaTheme {
                MuwaLaunchHost(showIntro = showIntro, systemLaunchReady = systemLaunchReady) {
                    MuwaApp(
                        initialRoute = reviewRoute?.takeUnless { it == "launch" } ?: "home",
                        requestNotifications = {
                            if (Build.VERSION.SDK_INT >= 33)
                                notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
                        },
                    )
                }
            }
        }
    }
}
