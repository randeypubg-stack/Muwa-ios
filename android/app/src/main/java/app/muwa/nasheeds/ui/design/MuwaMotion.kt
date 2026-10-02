package app.muwa.nasheeds.ui.design

import android.animation.ValueAnimator
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.animation.core.spring
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

object MuwaMotion {
    const val AmbientDuration = 24_000

    fun press() = spring<Float>(dampingRatio = 0.78f, stiffness = 620f)
}

@Composable
internal fun rememberAmbientMotionAllowed(): Boolean {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val power = remember(context) { context.getSystemService(PowerManager::class.java) }
    var allowed by remember { mutableStateOf(false) }
    DisposableEffect(context, lifecycle) {
        fun refresh() {
            allowed =
                lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) &&
                    !power.isPowerSaveMode &&
                    ValueAnimator.areAnimatorsEnabled()
        }
        val lifecycleObserver = LifecycleEventObserver { _, _ -> refresh() }
        val receiver =
            object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) = refresh()
            }
        val scaleObserver =
            object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) = refresh()
            }
        lifecycle.addObserver(lifecycleObserver)
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        context.contentResolver.registerContentObserver(
            Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
            false,
            scaleObserver,
        )
        refresh()
        onDispose {
            lifecycle.removeObserver(lifecycleObserver)
            context.unregisterReceiver(receiver)
            context.contentResolver.unregisterContentObserver(scaleObserver)
        }
    }
    return allowed
}
