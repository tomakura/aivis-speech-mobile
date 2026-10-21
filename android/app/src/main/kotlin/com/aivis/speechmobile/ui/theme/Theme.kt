package com.aivis.speechmobile.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

data class AivisColors(
    val accent: Color,
    val editorAccent: Color,
    val success: Color,
    val warning: Color,
    val background: Color,
    val surface: Color,
    val secondarySurface: Color,
    val border: Color,
    val accentMuted: Color,
    val mutedText: Color,
)

val LocalAivisColors = staticCompositionLocalOf {
    AivisColors(
        accent = AivisAccent,
        editorAccent = AivisEditorAccent,
        success = AivisSuccess,
        warning = AivisWarning,
        background = AivisBackgroundLight,
        surface = AivisSurfaceLight,
        secondarySurface = AivisSecondarySurfaceLight,
        border = AivisBorderLight,
        accentMuted = AivisAccentMutedLight,
        mutedText = Color(0xFF888888),
    )
}

private val lightColors = lightColorScheme(
    primary = AivisAccent,
    onPrimary = Color.White,
    secondary = AivisAccent,
    background = AivisBackgroundLight,
    surface = AivisSurfaceLight,
    onBackground = Color(0xFF1A1A1A),
    onSurface = Color(0xFF1A1A1A),
)

private val darkColors = darkColorScheme(
    primary = AivisAccent,
    onPrimary = Color.White,
    secondary = AivisAccent,
    background = AivisBackgroundDark,
    surface = AivisSurfaceDark,
    onBackground = Color(0xFFEEEEEE),
    onSurface = Color(0xFFEEEEEE),
)

@Composable
fun AivisSpeechTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) darkColors else lightColors
    val aivisColors = if (darkTheme) {
        AivisColors(
            accent = AivisAccent,
            editorAccent = AivisEditorAccent,
            success = AivisSuccess,
            warning = AivisWarning,
            background = AivisBackgroundDark,
            surface = AivisSurfaceDark,
            secondarySurface = AivisSecondarySurfaceDark,
            border = AivisBorderDark,
            accentMuted = AivisAccentMutedDark,
            mutedText = Color(0xFF9E9E9E),
        )
    } else {
        AivisColors(
            accent = AivisAccent,
            editorAccent = AivisEditorAccent,
            success = AivisSuccess,
            warning = AivisWarning,
            background = AivisBackgroundLight,
            surface = AivisSurfaceLight,
            secondarySurface = AivisSecondarySurfaceLight,
            border = AivisBorderLight,
            accentMuted = AivisAccentMutedLight,
            mutedText = Color(0xFF6E6E6E),
        )
    }

    CompositionLocalProvider(LocalAivisColors provides aivisColors) {
        MaterialTheme(
            colorScheme = colorScheme,
            content = content,
        )
    }
}
