package com.rodwave.studio.ui.icon

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The Rodwave mark, drawn entirely in code: a synthwave sun over a neon grid with a bold "R" whose
 * leg turns into a wave. The same geometry (108 x 108 units) is used by the Android adaptive
 * launcher icon in res/drawable.
 */
object RodwaveMark {
    /** Letter paths in the 108-unit icon space (also used by the vector drawables). */
    const val STEM = "M40,33 L40,75"
    const val BOWL = "M40,33 L52,33 A10.5,10.5 0 0 1 52,54 L40,54"
    const val LEG = "M48,54 C55,56 57,64 60,68 S66,74 71,74"

    val sky = Brush.verticalGradient(listOf(Color(0xFF2B0A3D), Color(0xFF14082A), Color(0xFF0A0B1A)))
    val sun = Brush.verticalGradient(listOf(Color(0xFFFFD27A), Color(0xFFFF8A3D), Color(0xFFFF3D8B)), startY = 20f, endY = 80f)
    val letter = Brush.linearGradient(listOf(Color.White, Color(0xFFFFE3F0)), start = Offset(36f, 30f), end = Offset(76f, 78f))
    val grid = Color(0x66FF3D8B)
    val glow = Color(0x33FF3D8B)
}

@Composable
fun RodwaveLogo(modifier: Modifier = Modifier, size: Dp = 96.dp, rounded: Boolean = true) {
    val stem = remember { PathParser().parsePathString(RodwaveMark.STEM).toPath() }
    val bowl = remember { PathParser().parsePathString(RodwaveMark.BOWL).toPath() }
    val leg = remember { PathParser().parsePathString(RodwaveMark.LEG).toPath() }
    Canvas(modifier.size(size)) {
        val scale = this.size.minDimension / 108f
        val clip = Path().apply {
            if (rounded) {
                addRoundRect(androidx.compose.ui.geometry.RoundRect(0f, 0f, this@Canvas.size.width, this@Canvas.size.height, CornerRadius(this@Canvas.size.minDimension * 0.24f)))
            } else {
                addRect(androidx.compose.ui.geometry.Rect(0f, 0f, this@Canvas.size.width, this@Canvas.size.height))
            }
        }
        clipPath(clip) {
            withTransform({ scale(scale, scale, pivot = Offset.Zero) }) {
                drawBackground()
                drawLetter(stem, bowl, leg)
            }
        }
    }
}

private fun DrawScope.drawBackground() {
    drawRect(RodwaveMark.sky, size = Size(108f, 108f))
    // Glow behind the sun.
    drawCircle(RodwaveMark.glow, radius = 38f, center = Offset(54f, 50f))
    // Synthwave sun with horizontal cut-outs in its lower half.
    drawCircle(RodwaveMark.sun, radius = 30f, center = Offset(54f, 50f))
    val cut = Color(0xFF1A0A2E)
    listOf(56f to 1.6f, 62f to 2.2f, 68f to 2.8f, 74f to 3.4f).forEach { (y, h) ->
        drawRect(cut, topLeft = Offset(20f, y), size = Size(68f, h))
    }
    // Horizon and perspective grid.
    drawRect(Color(0xFF0A0B1A), topLeft = Offset(0f, 80f), size = Size(108f, 28f))
    drawLine(Color(0xFFFF3D8B), Offset(0f, 80f), Offset(108f, 80f), strokeWidth = 1.2f)
    listOf(84f, 89f, 95f, 102f).forEach { y -> drawLine(RodwaveMark.grid, Offset(0f, y), Offset(108f, y), strokeWidth = 0.8f) }
    for (i in -4..4) {
        drawLine(RodwaveMark.grid, Offset(54f + i * 6f, 80f), Offset(54f + i * 22f, 108f), strokeWidth = 0.8f)
    }
}

private fun DrawScope.drawLetter(stem: Path, bowl: Path, leg: Path) {
    val shadow = Stroke(width = 11f, cap = StrokeCap.Round, join = StrokeJoin.Round)
    val stroke = Stroke(width = 8f, cap = StrokeCap.Round, join = StrokeJoin.Round)
    // Soft dark outline keeps the letter readable over the sun.
    listOf(stem, bowl, leg).forEach { drawPath(it, Color(0x99140818), style = shadow) }
    listOf(stem, bowl, leg).forEach { drawPath(it, RodwaveMark.letter, style = stroke) }
}
