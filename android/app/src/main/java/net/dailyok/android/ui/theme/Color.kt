package net.dailyok.android.ui.theme

import androidx.compose.ui.graphics.Color

// Brand green tonal ramp (Daily OK premium palette)
val DailyOKGreen50 = Color(0xFFF0FDF4)
val DailyOKGreen100 = Color(0xFFDCFCE7)
val DailyOKGreen200 = Color(0xFFBBF7D0)
val DailyOKGreen300 = Color(0xFF86EFAC)
val DailyOKGreen400 = Color(0xFF4ADE80)
val DailyOKGreen500 = Color(0xFF22C55E)
val DailyOKGreen600 = Color(0xFF16A34A)
val DailyOKGreen700 = Color(0xFF15803D)
val DailyOKGreen800 = Color(0xFF166534)
val DailyOKGreen900 = Color(0xFF14532D)

// Legacy aliases (retained for backwards compatibility with existing screens)
val DailyOKGreen = DailyOKGreen500
val DailyOKGreenDark = DailyOKGreen600
val DailyOKGreenLight = DailyOKGreen300
val DailyOKGreenContainer = DailyOKGreen100

// Premium accent colors
val DailyOKTeal = Color(0xFF14B8A6)       // Secondary accent for analytics/charts
val DailyOKGold = Color(0xFFF59E0B)       // Paid / premium feature highlight
val DailyOKGoldLight = Color(0xFFFDE68A)
val DailyOKIndigo = Color(0xFF6366F1)     // Optional accent for informational chips

val White = Color(0xFFFFFFFF)
val Black = Color(0xFF000000)
val Gray50 = Color(0xFFF9FAFB)
val Gray100 = Color(0xFFF3F4F6)
val Gray200 = Color(0xFFE5E7EB)
val Gray300 = Color(0xFFD1D5DB)
val Gray400 = Color(0xFF9CA3AF)
val Gray500 = Color(0xFF6B7280)
val Gray700 = Color(0xFF374151)
val Gray800 = Color(0xFF1F2937)
val Gray900 = Color(0xFF111827)
val Gray950 = Color(0xFF0A0F1A)

// Tonal surfaces — enables layered elevation on both light and dark themes.
val SurfaceLight = White
val SurfaceLightLow = Gray50
val SurfaceLightMed = Gray100
val SurfaceLightHigh = Gray200

// Branded dark surfaces: subtly tinted toward brand green rather than pure neutral grays.
val SurfaceDark = Color(0xFF0B1410)
val SurfaceDarkLow = Color(0xFF0F1A14)
val SurfaceDarkMed = Color(0xFF142219)
val SurfaceDarkHigh = Color(0xFF1B2C22)

val ErrorRed = Color(0xFFEF4444)
val ErrorRedDark = Color(0xFFB91C1C)
val WarningOrange = Color(0xFFF59E0B)
val InfoBlue = Color(0xFF3B82F6)

// Status card background tints
val StatusGreenBg = DailyOKGreen100
val StatusYellowBg = Color(0xFFFEF9C3)
val StatusRedBg = Color(0xFFFEE2E2)
val StatusGrayBg = Gray100

// Status card background tints (dark theme)
val StatusGreenBgDark = DailyOKGreen900
val StatusYellowBgDark = Color(0xFF713F12)
val StatusRedBgDark = Color(0xFF7F1D1D)
val StatusGrayBgDark = Color(0xFF374151)
