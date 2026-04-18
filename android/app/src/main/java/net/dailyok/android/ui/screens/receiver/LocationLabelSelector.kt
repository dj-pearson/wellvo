package net.dailyok.android.ui.screens.receiver

import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.res.stringResource
import net.dailyok.android.R
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import net.dailyok.android.ui.components.GlassCard
import net.dailyok.android.ui.theme.DailyOKElevation
import net.dailyok.android.ui.theme.DailyOKGlass
import net.dailyok.android.ui.theme.DailyOKGlassStyle

data class LocationOption(
    val id: String,
    val label: String,
    val emoji: String
)

private val locationOptions = listOf(
    LocationOption("home", "Home", "\uD83C\uDFE0"),
    LocationOption("school", "School", "\uD83C\uDFEB"),
    LocationOption("friends_house", "Friend's House", "\uD83C\uDFE1"),
    LocationOption("park", "Park", "\uD83C\uDF33"),
    LocationOption("store", "Store", "\uD83C\uDFEA"),
    LocationOption("other", "Other", "\uD83D\uDCCD")
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LocationLabelSelector(
    selectedLabel: String?,
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
            text = stringResource(R.string.location_where),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(16.dp))

        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            locationOptions.forEach { option ->
                OutlinedCard(
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onSelect(option.id)
                    },
                    modifier = Modifier
                        .padding(4.dp)
                        .width(100.dp),
                    border = BorderStroke(
                        width = if (selectedLabel == option.id) 2.dp else 1.dp,
                        color = if (selectedLabel == option.id) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.outline
                    )
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(text = option.emoji, fontSize = 28.sp)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = option.label,
                            style = MaterialTheme.typography.bodySmall,
                            textAlign = TextAlign.Center
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        if (selectedLabel != null) {
            Button(onClick = {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                onSubmit()
            }, modifier = Modifier.fillMaxWidth()) {
                Text("Submit Location")
            }
            Spacer(modifier = Modifier.height(4.dp))
        }

        TextButton(onClick = onSkip) {
            Text("Skip")
        }
    }
    }
}
