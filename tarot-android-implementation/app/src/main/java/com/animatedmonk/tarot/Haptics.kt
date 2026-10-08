package com.animatedmonk.tarot

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import app.rive.ViewModelInstance
import kotlinx.coroutines.launch

/**
 * Haptics driven by the .riv: the file fires view model triggers at exact
 * frames, and the app decides how each one feels.
 *   hapticTick         a card is picked          short tick
 *   hapticChargeStart  the charge begins         rising rumble (about the charge's 2.3s)
 *   hapticImpact       the burst explodes        heavy click
 *   revealed           the card lands face up    soft thud
 */
@Composable
fun RiveHaptics(vmi: ViewModelInstance) {
    val context = LocalContext.current
    LaunchedEffect(vmi) {
        val vibrator = vibrator(context) ?: return@LaunchedEffect
        if (!vibrator.hasVibrator()) {
            return@LaunchedEffect
        }
        val cues = mapOf(
            "hapticTick" to { tick() },
            "hapticChargeStart" to { rumble() },
            "hapticImpact" to { impact() },
            "revealed" to { thud() },
        )
        for ((trigger, effect) in cues) {
            launch {
                vmi.getTriggerFlow(trigger).collect {
                    Log.i("TarotHaptics", trigger)
                    vibrator.cancel()
                    vibrator.vibrate(effect())
                }
            }
        }
    }
}

private fun vibrator(context: Context): Vibrator? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        context.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Vibrator::class.java)
    }

private fun tick(): VibrationEffect =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK)
    } else {
        VibrationEffect.createOneShot(15, 120)
    }

private fun impact(): VibrationEffect =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK)
    } else {
        VibrationEffect.createOneShot(60, 255)
    }

private fun thud(): VibrationEffect = VibrationEffect.createOneShot(40, 160)

/** Builds from faint to strong over about 2.2s, ending just before the burst. */
private fun rumble(): VibrationEffect {
    val steps = 11
    val timings = LongArray(steps) { 200L }
    val amplitudes = IntArray(steps) { i -> 20 + (i * 200 / (steps - 1)) }
    return VibrationEffect.createWaveform(timings, amplitudes, -1)
}
