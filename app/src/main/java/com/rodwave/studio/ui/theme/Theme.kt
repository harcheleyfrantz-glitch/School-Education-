package com.rodwave.studio.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rodwave.engine.compat.ComponentState
import com.rodwave.engine.editor.SyntaxStyle
import com.rodwave.studio.core.ThemeVariant

object Palette {
    val Sunset = Color(0xFFFF6B3D)
    val Pink = Color(0xFFFF3D8B)
    val Violet = Color(0xFF9B5CFF)
    val Teal = Color(0xFF39E6C2)
    val Gold = Color(0xFFFFC24B)
    val Sky = Color(0xFF5AB2FF)
    val Red = Color(0xFFFF5370)
    val Green = Color(0xFF3DDC97)
    val Slate = Color(0xFF7C849C)
    val Lavender = Color(0xFFB48CFF)

    val brandGradient = Brush.linearGradient(listOf(Color(0xFFFFB347), Sunset, Pink, Violet))
    val sunGradient = Brush.verticalGradient(listOf(Color(0xFFFFD27A), Color(0xFFFF8A3D), Pink))
}

@Immutable
data class SyntaxColors(
    val keyword: Color,
    val command: Color,
    val opcode: Color,
    val label: Color,
    val globalVar: Color,
    val localVar: Color,
    val number: Color,
    val string: Color,
    val comment: Color,
    val directive: Color,
    val operator: Color,
    val model: Color,
    val constant: Color,
    val error: Color,
    val plain: Color,
    val caretLine: Color,
    val bracket: Color,
    val searchMatch: Color,
    val searchCurrent: Color,
    val gutter: Color,
    val gutterText: Color,
) {
    fun of(style: SyntaxStyle): Color = when (style) {
        SyntaxStyle.KEYWORD -> keyword
        SyntaxStyle.COMMAND -> command
        SyntaxStyle.OPCODE -> opcode
        SyntaxStyle.LABEL -> label
        SyntaxStyle.GLOBAL_VAR -> globalVar
        SyntaxStyle.LOCAL_VAR -> localVar
        SyntaxStyle.NUMBER -> number
        SyntaxStyle.STRING -> string
        SyntaxStyle.COMMENT -> comment
        SyntaxStyle.DIRECTIVE -> directive
        SyntaxStyle.OPERATOR -> operator
        SyntaxStyle.MODEL -> model
        SyntaxStyle.CONSTANT -> constant
        SyntaxStyle.ERROR -> error
        SyntaxStyle.PLAIN -> plain
    }

    companion object {
        val Default = SyntaxColors(
            keyword = Color(0xFFFF79C6),
            command = Color(0xFF82AAFF),
            opcode = Color(0xFFFFB86C),
            label = Color(0xFFFFD866),
            globalVar = Color(0xFFC3E88D),
            localVar = Color(0xFF89DDFF),
            number = Color(0xFFF78C6C),
            string = Color(0xFFECC48D),
            comment = Color(0xFF6C7A96),
            directive = Color(0xFFC792EA),
            operator = Color(0xFF89DDFF),
            model = Color(0xFFFF9CAC),
            constant = Color(0xFFF78C6C),
            error = Color(0xFFFF5370),
            plain = Color(0xFFE6E8F2),
            caretLine = Color(0x14FFFFFF),
            bracket = Color(0x5539E6C2),
            searchMatch = Color(0x55FFC24B),
            searchCurrent = Color(0xAAFF6B3D),
            gutter = Color(0xFF0E1019),
            gutterText = Color(0xFF59607A),
        )
    }
}

val LocalSyntaxColors = staticCompositionLocalOf { SyntaxColors.Default }

val CodeFont: FontFamily = FontFamily.Monospace

fun stateColor(state: ComponentState): Color = when (state) {
    ComponentState.COMPATIBLE -> Palette.Green
    ComponentState.PARTIALLY_COMPATIBLE -> Palette.Gold
    ComponentState.INSTALLED_UNVERIFIED -> Palette.Sky
    ComponentState.NOT_DETECTED -> Palette.Slate
    ComponentState.INCOMPATIBLE -> Palette.Red
    ComponentState.UNKNOWN -> Palette.Lavender
}

private fun scheme(variant: ThemeVariant): ColorScheme = when (variant) {
    ThemeVariant.SUNSET -> darkColorScheme(
        primary = Palette.Sunset,
        onPrimary = Color(0xFF1A0B05),
        primaryContainer = Color(0xFF4A1E12),
        onPrimaryContainer = Color(0xFFFFDBCF),
        secondary = Palette.Pink,
        onSecondary = Color(0xFF250014),
        secondaryContainer = Color(0xFF4A1230),
        onSecondaryContainer = Color(0xFFFFD9E6),
        tertiary = Palette.Teal,
        onTertiary = Color(0xFF00201A),
        tertiaryContainer = Color(0xFF0F3D35),
        onTertiaryContainer = Color(0xFFB8FFEC),
        background = Color(0xFF0A0B12),
        onBackground = Color(0xFFE8EAF2),
        surface = Color(0xFF0F111B),
        onSurface = Color(0xFFE8EAF2),
        surfaceVariant = Color(0xFF1A1E2D),
        onSurfaceVariant = Color(0xFF9AA3BD),
        surfaceContainerLowest = Color(0xFF080910),
        surfaceContainerLow = Color(0xFF11131E),
        surfaceContainer = Color(0xFF151827),
        surfaceContainerHigh = Color(0xFF1B1F30),
        surfaceContainerHighest = Color(0xFF222739),
        outline = Color(0xFF2E3550),
        outlineVariant = Color(0xFF232838),
        error = Palette.Red,
        onError = Color(0xFF2A0008),
        errorContainer = Color(0xFF4D1220),
        onErrorContainer = Color(0xFFFFDADF),
    )
    ThemeVariant.MIDNIGHT -> scheme(ThemeVariant.SUNSET).copy(
        primary = Palette.Sky,
        onPrimary = Color(0xFF00213D),
        primaryContainer = Color(0xFF123456),
        secondary = Palette.Violet,
        background = Color(0xFF070B18),
        surface = Color(0xFF0B1022),
        surfaceContainer = Color(0xFF111833),
        surfaceContainerHigh = Color(0xFF16203F),
        surfaceContainerHighest = Color(0xFF1C2850),
        surfaceVariant = Color(0xFF16203F),
    )
    ThemeVariant.AMOLED -> scheme(ThemeVariant.SUNSET).copy(
        background = Color.Black,
        surface = Color.Black,
        surfaceContainerLowest = Color.Black,
        surfaceContainerLow = Color(0xFF07070A),
        surfaceContainer = Color(0xFF0C0C11),
        surfaceContainerHigh = Color(0xFF121218),
        surfaceContainerHighest = Color(0xFF18181F),
        surfaceVariant = Color(0xFF121218),
    )
}

private val RodwaveTypography = Typography().let { base ->
    base.copy(
        displaySmall = base.displaySmall.copy(fontWeight = FontWeight.Black, letterSpacing = (-0.5).sp),
        headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.25).sp),
        headlineSmall = base.headlineSmall.copy(fontWeight = FontWeight.Bold),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.Bold),
        titleMedium = base.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        labelLarge = base.labelLarge.copy(fontWeight = FontWeight.SemiBold),
    )
}

private val RodwaveShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp),
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

val CodeTextStyle = TextStyle(fontFamily = CodeFont)

@Composable
fun RodwaveTheme(variant: ThemeVariant = ThemeVariant.SUNSET, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme(variant), typography = RodwaveTypography, shapes = RodwaveShapes) {
        CompositionLocalProvider(LocalSyntaxColors provides SyntaxColors.Default, content = content)
    }
}
