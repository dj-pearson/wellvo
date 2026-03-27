package net.wellvo.android.ui.screens.receiver

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Where are you?",
            style = MaterialTheme.typography.titleMedium
        )
        Spacer(modifier = Modifier.height(16.dp))

        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            locationOptions.forEach { option ->
                OutlinedCard(
                    onClick = { onSelect(option.id) },
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
            Button(onClick = onSubmit, modifier = Modifier.fillMaxWidth()) {
                Text("Submit Location")
            }
            Spacer(modifier = Modifier.height(4.dp))
        }

        TextButton(onClick = onSkip) {
            Text("Skip")
        }
    }
}
