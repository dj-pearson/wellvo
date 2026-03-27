package net.wellvo.android.ui.screens.receiver

import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.unit.dp

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

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Need anything?",
            style = MaterialTheme.typography.titleMedium
        )
        Spacer(modifier = Modifier.height(16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            kidResponseOptions.forEach { option ->
                val isSelected = selectedResponse == option.id
                OutlinedButton(
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        onSelect(option.id)
                    },
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = 4.dp),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = if (isSelected) option.color.copy(alpha = 0.15f) else Color.Transparent,
                        contentColor = option.color
                    )
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
