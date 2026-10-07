package com.animatedmonk.tarot

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Home: today's date and the Daily Divination promo. Before a draw it opens
 * the picker ("Draw Card"); once today's card is drawn it shows that card and
 * reopens the reading ("Read More"), as on the web demo.
 */
@Composable
fun HomeScreen(drawn: Persona?, onDraw: () -> Unit, onReadMore: () -> Unit) {
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
            alpha = 0.55f,
        )
        Column(
            Modifier
                .fillMaxSize()
                .safeDrawingPadding()
                .padding(horizontal = 20.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    LocalDate.now().format(DateTimeFormatter.ofPattern("EEEE, d MMMM")).uppercase(),
                    color = Color(0xFFA39FC0),
                    fontSize = 12.sp,
                    letterSpacing = 1.6.sp,
                )
                Text(
                    "Good day",
                    color = Color(0xFFF3EEDD),
                    fontSize = 32.sp,
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.Medium,
                )
            }
            Promo(drawn, if (drawn == null) onDraw else onReadMore)
            Text(
                if (drawn == null) {
                    "One card a day. Take a breath, then pick the one that calls to you."
                } else {
                    "Today's card is drawn. Come back tomorrow for a new one."
                },
                color = Color(0xFFD9D4EC),
                fontSize = 15.sp,
                lineHeight = 22.sp,
            )
        }
    }
}

@Composable
private fun Promo(drawn: Persona?, onClick: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .border(BorderStroke(1.dp, Color(0x66E8C27A)), shape)
            .clickable(role = Role.Button, onClick = onClick),
    ) {
        Image(
            bitmap = rememberAssetImage("images/promo-bg.png"),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.matchParentSize(),
        )
        Row(
            Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(
                bitmap = rememberAssetImage(drawn?.imagePath ?: "images/promo-card.png"),
                contentDescription = drawn?.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(width = 72.dp, height = 112.dp)
                    .clip(RoundedCornerShape(8.dp)),
            )
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    "Daily Divination",
                    color = Color(0xFFF3EEDD),
                    fontSize = 20.sp,
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    drawn?.name ?: "What does today have in store for you? Pick a card to find out.",
                    color = Color(0xFFD9D4EC),
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    if (drawn == null) "Draw Card" else "Read More",
                    color = Color(0xFF14122B),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color(0xFFE8C27A))
                        .padding(horizontal = 14.dp, vertical = 7.dp),
                )
            }
        }
    }
}
