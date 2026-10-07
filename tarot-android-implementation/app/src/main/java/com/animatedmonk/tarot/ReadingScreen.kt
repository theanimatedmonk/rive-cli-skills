package com.animatedmonk.tarot

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Text = Color(0xFFD9D4EC)
private val Muted = Color(0xFFA39FC0)
private val Panel = Color(0xCC1E1B3A)
private val Gold = Color(0xFFE8C27A)

/**
 * The reading (the web demo's "H · Orbit" layout): the card in the middle,
 * Career, Love and Finance as planets around it, and the chosen planet's
 * reading in the panel below. Share opens the system share sheet.
 */
@Composable
fun ReadingScreen(persona: Persona, number: String, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    var topic by rememberSaveable { mutableStateOf(Topic.Career) }
    val context = LocalContext.current

    Box(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF0A0811)),
    ) {
        Image(
            bitmap = rememberAssetImage("images/bg.png"),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Column(
            Modifier
                .fillMaxSize()
                .safeDrawingPadding()
                .padding(horizontal = 24.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                IconButton(onClick = onDone, modifier = Modifier.offset(x = (-12).dp)) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Text)
                }
                Text(
                    "TODAY'S CARD · $number",
                    color = Muted,
                    fontSize = 12.sp,
                    letterSpacing = 1.7.sp,
                )
            }

            Orbit(persona, topic, onSelect = { topic = it })

            ReadingPanel(persona, topic, Modifier.weight(1f))

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    onClick = {
                        val text = "My tarot card today: ${persona.name}.\n\n${topic.title}: ${persona.text(topic)}"
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                        context.startActivity(Intent.createChooser(send, "Share your reading"))
                    },
                    modifier = Modifier
                        .weight(1f)
                        .height(52.dp),
                    shape = RoundedCornerShape(14.dp),
                    border = BorderStroke(1.dp, Color(0xFF3A3566)),
                    colors = ButtonDefaults.outlinedButtonColors(containerColor = Panel, contentColor = Text),
                ) {
                    Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text("  Share", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
                Button(
                    onClick = onDone,
                    modifier = Modifier
                        .weight(1f)
                        .height(52.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Gold, contentColor = Color(0xFF14122B)),
                ) {
                    Text("Done", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

/** The card at the centre of a dashed orbit, with a planet per topic. */
@Composable
private fun Orbit(persona: Persona, selected: Topic, onSelect: (Topic) -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(300.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(width = 312.dp, height = 300.dp)) {
            Canvas(Modifier.fillMaxSize()) {
                val centre = Offset(size.width / 2, size.height / 2)
                drawCircle(
                    color = Color(0xFF3A3566),
                    radius = 115.dp.toPx(),
                    center = centre,
                    style = Stroke(
                        width = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())),
                    ),
                )
                drawCircle(color = Color(0x0DE8C27A), radius = 70.dp.toPx(), center = centre)
                drawCircle(
                    color = Color(0xFF262248),
                    radius = 70.dp.toPx(),
                    center = centre,
                    style = Stroke(width = 1.dp.toPx()),
                )
            }
            Column(
                Modifier
                    .align(Alignment.Center)
                    .offset(y = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Image(
                    bitmap = rememberAssetImage(persona.imagePath),
                    contentDescription = persona.name,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(width = 64.dp, height = 100.dp)
                        .clip(RoundedCornerShape(6.dp)),
                )
                Text(
                    persona.name,
                    color = Color(0xFFF3EEDD),
                    fontSize = 15.sp,
                    fontFamily = FontFamily.Serif,
                )
            }
            Planet(Topic.Career, selected == Topic.Career, onSelect, Modifier.offset(x = 112.dp, y = 0.dp))
            Planet(Topic.Love, selected == Topic.Love, onSelect, Modifier.offset(x = 12.dp, y = 178.dp))
            Planet(Topic.Finance, selected == Topic.Finance, onSelect, Modifier.offset(x = 212.dp, y = 178.dp))
        }
    }
}

@Composable
private fun Planet(topic: Topic, selected: Boolean, onSelect: (Topic) -> Unit, modifier: Modifier) {
    Column(
        modifier
            .width(88.dp)
            .selectable(selected = selected, role = Role.Tab, onClick = { onSelect(topic) }),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            Modifier
                .size(60.dp)
                .clip(CircleShape)
                .background(if (selected) topic.color else Color(0xE61E1B3A))
                .border(1.dp, topic.color.copy(alpha = 0.6f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                topicIcon(topic),
                contentDescription = null,
                tint = if (selected) Color(0xFF14122B) else topic.color,
                modifier = Modifier.size(24.dp),
            )
        }
        Text(
            topic.title.uppercase(),
            color = topic.color,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 1.sp,
        )
    }
}

@Composable
private fun ReadingPanel(persona: Persona, topic: Topic, modifier: Modifier) {
    val shape = RoundedCornerShape(20.dp)
    AnimatedContent(
        targetState = topic,
        transitionSpec = { fadeIn() togetherWith fadeOut() },
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Panel)
            .border(1.dp, topic.color.copy(alpha = 0.4f), shape),
        label = "reading",
    ) { current ->
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 22.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                current.title,
                color = current.color,
                fontSize = 24.sp,
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.SemiBold,
            )
            Text(persona.text(current), color = Text, fontSize = 15.sp, lineHeight = 24.sp)
        }
    }
}
