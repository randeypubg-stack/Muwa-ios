package app.muwa.nasheeds.ui.state

import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf

@Composable
fun <T> rememberSaveableState(initial: T): MutableState<T> =
    androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(initial) }
