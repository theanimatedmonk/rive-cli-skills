package com.animatedmonk.tarot

import android.content.Context
import androidx.compose.ui.graphics.Color
import org.json.JSONArray

/** One of the 22 Major Arcana, from assets/personas.json (synced from the web demo). */
data class Persona(
    val image: String,
    val name: String,
    val career: String,
    val love: String,
    val finance: String,
) {
    /** Path of the card face in assets. */
    val imagePath get() = "cards/$image"

    fun text(topic: Topic) = when (topic) {
        Topic.Career -> career
        Topic.Love -> love
        Topic.Finance -> finance
    }
}

enum class Topic(val title: String, val color: Color) {
    Career("Career", Color(0xFFE8C27A)),
    Love("Love", Color(0xFFEFA3AE)),
    Finance("Finance", Color(0xFF8ED1B6)),
}

val ROMAN = listOf(
    "0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
    "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI",
)

fun loadPersonas(context: Context): List<Persona> {
    val json = context.assets.open("personas.json").bufferedReader().use { it.readText() }
    val array = JSONArray(json)
    return List(array.length()) { i ->
        val o = array.getJSONObject(i)
        Persona(
            image = o.getString("image"),
            name = o.getString("name"),
            career = o.getString("career"),
            love = o.getString("love"),
            finance = o.getString("finance"),
        )
    }
}
