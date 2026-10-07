package com.animatedmonk.tarot

import android.graphics.BitmapFactory
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext

/** Decodes an image from app assets once per path. */
@Composable
fun rememberAssetImage(path: String): ImageBitmap {
    val context = LocalContext.current
    return remember(path) {
        context.assets.open(path).use { BitmapFactory.decodeStream(it) }.asImageBitmap()
    }
}
