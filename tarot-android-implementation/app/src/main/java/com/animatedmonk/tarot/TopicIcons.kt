package com.animatedmonk.tarot

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

// The web demo's planet icons (24x24 line icons), as Compose vectors.
private val ICON_PATHS = mapOf(
    // Briefcase: body, handle and the band across it.
    Topic.Career to listOf(
        "M5 7h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z",
        "M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 13h18",
    ),
    Topic.Love to listOf(
        "M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z",
    ),
    // Coin with a dollar sign.
    Topic.Finance to listOf(
        "M20.5 12a8.5 8.5 0 1 1-17 0a8.5 8.5 0 1 1 17 0z",
        "M14.5 9.5c-.5-.9-1.5-1.5-2.5-1.5-1.4 0-2.5.8-2.5 2s1.1 1.6 2.5 2 2.5.8 2.5 2-1.1 2-2.5 2c-1 0-2-.6-2.5-1.5M12 6.5v11",
    ),
)

private val cache = mutableMapOf<Topic, ImageVector>()

/** Stroke icon for [topic]; tint it with Icon's tint. */
fun topicIcon(topic: Topic): ImageVector = cache.getOrPut(topic) {
    val builder = ImageVector.Builder(
        name = topic.title,
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    )
    for (d in ICON_PATHS.getValue(topic)) {
        builder.addPath(
            pathData = PathParser().parsePathString(d).toNodes(),
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 1.6f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        )
    }
    builder.build()
}
