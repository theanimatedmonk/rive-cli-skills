package com.animatedmonk.tarot

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import app.rive.RenderBackend
import app.rive.Result
import app.rive.RiveFileSource
import app.rive.rememberRiveFile
import app.rive.rememberRiveWorker

/**
 * Daily Divination: Compose home and reading screens around the native Rive
 * card picker (PickerScreen). The .riv is the vector build of the tarot file
 * (./rive, the Rive CLI project), which skips GPU canvas shaders so the native
 * runtime renders it.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Dark screens throughout: light status and navigation bar icons.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        // Loads Rive's native library; must run before a worker is created.
        app.rive.runtime.kotlin.core.Rive.init(this)
        setContent { DailyDivination() }
    }
}

private enum class Screen { Home, Picker, Reading }

@Composable
private fun DailyDivination() {
    val context = LocalContext.current
    val personas = remember { loadPersonas(context) }
    // One Rive worker and file for the app, so reopening the picker is
    // instant. Vulkan where available; the runtime falls back to OpenGL.
    val worker = rememberRiveWorker(renderBackend = RenderBackend.Vulkan)
    val file = rememberRiveFile(RiveFileSource.RawRes.from(R.raw.tarot_animation), worker)
    var screen by rememberSaveable { mutableStateOf(Screen.Home) }
    // Today's card, once drawn (-1 = not yet). Nothing is stored: a fresh
    // launch starts fresh, as on the web demo.
    var drawn by rememberSaveable { mutableIntStateOf(-1) }
    val persona = personas.getOrNull(drawn)

    // A reading needs a drawn card.
    if (screen == Screen.Reading && persona == null) {
        LaunchedEffect(Unit) { screen = Screen.Home }
    }

    when (screen) {
        Screen.Home -> HomeScreen(
            drawn = persona,
            onDraw = { screen = Screen.Picker },
            onReadMore = { screen = Screen.Reading },
        )

        Screen.Picker -> if (file is Result.Success) {
            PickerScreen(
                worker = worker,
                file = file.value,
                personas = personas,
                onReading = { index ->
                    if (index in personas.indices) {
                        drawn = index
                        screen = Screen.Reading
                    }
                },
                onBack = { screen = Screen.Home },
            )
        }

        Screen.Reading -> persona?.let {
            ReadingScreen(it, ROMAN[drawn], onDone = { screen = Screen.Home })
        }
    }
}
