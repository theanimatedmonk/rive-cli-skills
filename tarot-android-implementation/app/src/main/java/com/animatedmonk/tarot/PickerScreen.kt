package com.animatedmonk.tarot

import android.util.Log
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rive.Fit
import app.rive.ImageAsset
import app.rive.Result
import app.rive.Rive
import app.rive.RiveFile
import app.rive.ViewModelInstance
import app.rive.ViewModelSource
import app.rive.core.RiveWorker
import app.rive.rememberArtboard
import app.rive.rememberStateMachine
import app.rive.rememberViewModelInstanceResult
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.merge

private const val TAG = "TarotPicker"
private const val ARTBOARD = "DailyDivination"
private const val STATE_MACHINE = "Divination"

// The .riv tells the app when to move on, through view model triggers fired
// from its timelines: `fanReady` once the fan has settled into FanIdle (a pick
// before that is swallowed by the state machine, so taps wait for it), and
// `revealed` when the flipped card has landed face up. The timeouts are only
// a safety net in case a trigger never arrives.
private const val FAN_READY_TIMEOUT_MS = 5000L
private const val REVEALED_TIMEOUT_MS = 6000L
// The face must be bound before the flip starts.
private const val REVEAL_DELAY_MS = 800L
private const val HEADING_FADE_MS = 500L

private val Cream = Color(0xFFF2ECFF)
private val Gold = Color(0xFFE8C27A)

private enum class Phase { Picking, Unfolding, Revealed }

/**
 * The Rive card picker, on the native Rive runtime. The file is the vector
 * build (./rive): no GPU canvas or shaders, so it renders on
 * Android. The heading, back button and "Reveal my reading" are Compose,
 * placed where the web demo puts them on its 360x780 stage.
 */
@Composable
fun PickerScreen(
    worker: RiveWorker,
    file: RiveFile,
    personas: List<Persona>,
    onReading: (personaIndex: Int) -> Unit,
    onBack: () -> Unit,
) {
    BackHandler(onBack = onBack)
    val artboard = rememberArtboard(file, ARTBOARD)
    val stateMachine = rememberStateMachine(artboard, STATE_MACHINE)
    val instance = rememberViewModelInstanceResult(
        file,
        ViewModelSource.DefaultForArtboard(artboard).defaultInstance(),
    )

    Box(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF0A0811)),
    ) {
        if (instance !is Result.Success) {
            return@Box
        }
        var phase by remember { mutableStateOf(Phase.Picking) }
        var picked by remember { mutableIntStateOf(-1) }
        var ready by remember { mutableStateOf(false) }
        LaunchedEffect(instance.value) {
            val signalled = withTimeoutOrNull(FAN_READY_TIMEOUT_MS) {
                instance.value.getTriggerFlow("fanReady").first()
            }
            Log.i(TAG, if (signalled != null) "fanReady" else "fanReady timed out")
            ready = true
        }
        RiveHaptics(instance.value)
        PickFlow(worker, instance.value, personas) { p, index ->
            phase = p
            picked = index
        }

        Rive(
            file = file,
            modifier = Modifier.fillMaxSize(),
            artboard = artboard,
            stateMachine = stateMachine,
            viewModelInstance = instance.value,
            fit = Fit.Cover(),
        )
        // Until the fan settles, and once a card is picked, swallow taps so
        // they never reach the cards.
        if (!ready || phase != Phase.Picking) {
            Box(
                Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        awaitPointerEventScope {
                            while (true) {
                                awaitPointerEvent().changes.forEach { it.consume() }
                            }
                        }
                    },
            )
        }

        Overlay(
            phase = phase,
            cardName = personas.getOrNull(picked)?.name.orEmpty(),
            onBack = onBack,
            onReveal = { onReading(picked) },
        )
    }
}

/**
 * Waits for the first pick (the card listeners fire pick1..pick5), binds a
 * random persona's face to the view model's `face`, fires `reveal`, then
 * reports the card when the file fires `revealed` (the card has landed).
 */
@Composable
private fun PickFlow(
    worker: RiveWorker,
    vmi: ViewModelInstance,
    personas: List<Persona>,
    onPhase: (Phase, Int) -> Unit,
) {
    val context = LocalContext.current
    val currentOnPhase by rememberUpdatedState(onPhase)
    var face by remember { mutableStateOf<ImageAsset?>(null) }
    DisposableEffect(Unit) {
        onDispose { face?.close() }
    }

    LaunchedEffect(vmi) {
        merge(*(1..5).map { vmi.getTriggerFlow("pick$it") }.toTypedArray()).first()

        val index = personas.indices.random()
        val persona = personas[index]
        Log.i(TAG, "picked -> ${persona.name}")
        currentOnPhase(Phase.Unfolding, index)

        val bytes = context.assets.open(persona.imagePath).use { it.readBytes() }
        when (val image = ImageAsset.fromBytes(worker, bytes)) {
            is Result.Success -> {
                face = image.value
                vmi.setImage("face", image.value)
            }
            is Result.Error -> Log.e(TAG, "Could not decode ${persona.imagePath}", image.throwable)
            is Result.Loading -> Unit
        }

        delay(REVEAL_DELAY_MS)
        coroutineScope {
            // Listen before firing, so the landing can't be missed.
            val landed = async { vmi.getTriggerFlow("revealed").first() }
            vmi.fireTrigger("reveal")
            val signalled = withTimeoutOrNull(REVEALED_TIMEOUT_MS) { landed.await() }
            if (signalled == null) {
                landed.cancel()
            }
            Log.i(TAG, if (signalled != null) "revealed" else "revealed timed out")
        }
        currentOnPhase(Phase.Revealed, index)
    }
}

/**
 * The web demo's picker chrome, on its 360x780 stage: app bar at 32, heading
 * at 116, result copy at 520 and the button at 644 (fractions of the height).
 */
@Composable
private fun Overlay(phase: Phase, cardName: String, onBack: () -> Unit, onReveal: () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val h = maxHeight
        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Cream)
            }
            Text(
                "Daily Divination",
                color = Cream,
                fontSize = 16.sp,
                fontFamily = FontFamily.Serif,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(48.dp))
        }

        Crossfade(
            targetState = phase,
            animationSpec = tween(HEADING_FADE_MS.toInt()),
            modifier = Modifier
                .fillMaxWidth()
                .offset(y = h * (116f / 780f)),
            label = "heading",
        ) { current ->
            Column(
                Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                when (current) {
                    Phase.Picking, Phase.Unfolding -> {
                        Text(
                            if (current == Phase.Picking) "Pick a card" else "Your reading is unfolding",
                            color = Cream,
                            fontSize = 28.sp,
                            fontFamily = FontFamily.Serif,
                            fontWeight = FontWeight.Medium,
                            textAlign = TextAlign.Center,
                        )
                        Text("—  ✦  —", color = Color(0xFFC9A84C), fontSize = 12.sp)
                        Text(
                            if (current == Phase.Picking) {
                                "Choose one card for today's reading."
                            } else {
                                "Take a breath while the card reveals itself."
                            },
                            color = Cream.copy(alpha = 0.8f),
                            fontSize = 15.sp,
                            fontFamily = FontFamily.Serif,
                            textAlign = TextAlign.Center,
                        )
                    }
                    Phase.Revealed -> {
                        Text(
                            cardName,
                            color = Cream,
                            fontSize = 30.sp,
                            fontFamily = FontFamily.Serif,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center,
                        )
                        Text("- Upright -", color = Cream, fontSize = 24.sp, fontFamily = FontFamily.Serif)
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = phase == Phase.Revealed,
            enter = fadeIn(tween(HEADING_FADE_MS.toInt())),
            exit = fadeOut(),
            modifier = Modifier
                .fillMaxWidth()
                .offset(y = h * (520f / 780f))
                .padding(horizontal = 18.dp),
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    "Tap the button below to view your divination results today",
                    color = Cream.copy(alpha = 0.8f),
                    fontSize = 15.sp,
                    lineHeight = 22.sp,
                    fontFamily = FontFamily.Serif,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 12.dp),
                )
                Spacer(Modifier.height(h * (124f / 780f) - 44.dp))
                Button(
                    onClick = onReveal,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Gold, contentColor = Color(0xFF14122B)),
                ) {
                    Text("Reveal my reading", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}
