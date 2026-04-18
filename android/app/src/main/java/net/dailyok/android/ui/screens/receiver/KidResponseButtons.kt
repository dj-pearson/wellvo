package net.dailyok.android.ui.screens.receiver

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.stringResource
import net.dailyok.android.R
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import net.dailyok.android.ui.components.GlassCard
import net.dailyok.android.ui.theme.DailyOKElevation
import net.dailyok.android.ui.theme.DailyOKGlass
import net.dailyok.android.ui.theme.DailyOKGlassStyle

private val PickUpColor = Color(0xFFF97316)   // orange
private val StayLongerColor = Color(0xFF3B82F6)  // blue
private val SosColor = Color(0xFFEF4444)  // red

data class KidResponseOption(
    val id: String,
    val label: String,
    val emoji: String,
    val color: Color
)

private val kidResponseOptions = listOf(
    KidResponseOption("picking_me_up", "Pick me up!", "\uD83D\uDE97", PickUpColor),
    KidResponseOption("can_stay_longer", "Can I stay longer?", "\u23F0", StayLongerColor),
    KidResponseOption("sos", "SOS!", "\u26A0\uFE0F", SosColor)
)

@Composable
fun KidResponseButtons(
    selectedResponse: String?,
    onSelect: (String) -> Unit,
    onSubmit: () -> Unit,
    onSkip: () -> Unit
) {
    val haptic = LocalHapticFeedback.current

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        style = DailyOKGlassStyle.Thin,
        shape = RoundedCornerShape(DailyOKGlass.RadiusLarge),
        elevation = DailyOKElevation.level2,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = stringResource(R.string.kid_need_anything),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(16.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                kidResponseOptions.forEach { option ->
                    val isSelected = selectedResponse == option.id
                    val isSos = option.id == "sos"
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = 4.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        // SOS gets an aurora halo to catch the eye
                        if (isSos) {
                            Box(
                                modifier = Modifier
                                    .size(90.dp)
                                    .scale(if (isSelected) 1.1f else 1.0f)
                                    .blur(radius = 18.dp)
                                    .background(option.color.copy(alpha = 0.5f), CircleShape)
                            )
                        }
                        OutlinedButton(
                            onClick = {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                onSelect(option.id)
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .then(
                                    if (isSelected)
                                        Modifier.background(
                                            Brush.linearGradient(
                                                listOf(option.color, option.color.copy(alpha = 0.7f))
                                            ),
                                            RoundedCornerShape(20.dp)
                                        )
                                    else Modifier
                                )
                                .border(
                                    width = 1.dp,
                                    color = option.color.copy(alpha = if (isSelected) 0f else 0.6f),
                                    shape = RoundedCornerShape(20.dp)
                                ),
                            shape = RoundedCornerShape(20.dp),
                            colors = ButtonDefaults.outlinedButtonColors(
                                containerColor = Color.Transparent,
                                contentColor = if (isSelected) Color.White else option.color
                            ),
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 10.dp)
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(text = option.emoji)
                                Text(
                                    text = option.label,
                                    style = MaterialTheme.typography.labelSmall
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            if (selectedResponse != null) {
                Button(onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onSubmit()
                }, modifier = Modifier.fillMaxWidth()) {
                    Text("Send")
                }
                Spacer(modifier = Modifier.height(4.dp))
            }

            TextButton(onClick = onSkip) {
                Text("Skip")
            }
        }
    }
}
