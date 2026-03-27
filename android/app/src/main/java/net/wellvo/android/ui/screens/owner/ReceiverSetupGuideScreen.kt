package net.wellvo.android.ui.screens.owner

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.GetApp
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Message
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

private val GuideGreen = Color(0xFF22C55E)
private val TipOrange = Color(0xFFF97316)

@Composable
fun ReceiverSetupGuideScreen(
    receiverName: String,
    onDone: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp)
    ) {
        // Header
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                modifier = Modifier.size(56.dp),
                tint = GuideGreen
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Invite Sent!",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "$receiverName will receive a text message with instructions to get started.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }

        Spacer(modifier = Modifier.height(24.dp))
        Divider()
        Spacer(modifier = Modifier.height(24.dp))

        // Steps header
        Text(
            text = "What $receiverName needs to do:",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(20.dp))

        SetupStepRow(
            stepNumber = 1,
            icon = Icons.Default.Message,
            title = "Open the Text Message",
            description = "$receiverName will receive a text with a link to download Wellvo from the Play Store."
        )

        Spacer(modifier = Modifier.height(16.dp))

        SetupStepRow(
            stepNumber = 2,
            icon = Icons.Default.GetApp,
            title = "Download the App",
            description = "Tap the link in the text to open the Play Store and download Wellvo."
        )

        Spacer(modifier = Modifier.height(16.dp))

        SetupStepRow(
            stepNumber = 3,
            icon = Icons.Default.Phone,
            title = "Sign In with Their Phone Number",
            description = "Open the app and enter the same phone number the text was sent to. They'll receive a verification code."
        )

        Spacer(modifier = Modifier.height(16.dp))

        SetupStepRow(
            stepNumber = 4,
            icon = Icons.Default.Notifications,
            title = "Allow Notifications",
            description = "The app will ask to send notifications. This is required so they receive their daily check-in reminder."
        )

        Spacer(modifier = Modifier.height(16.dp))

        SetupStepRow(
            stepNumber = 5,
            icon = Icons.Default.ThumbUp,
            title = "That's It!",
            description = "The app automatically connects them to your family. Each day at the scheduled time, they just tap \"I'm OK.\""
        )

        Spacer(modifier = Modifier.height(24.dp))
        Divider()
        Spacer(modifier = Modifier.height(24.dp))

        // Tips section
        Card(
            shape = MaterialTheme.shapes.medium,
            colors = CardDefaults.cardColors(
                containerColor = TipOrange.copy(alpha = 0.08f)
            )
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.Lightbulb,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = TipOrange
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Tips",
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = TipOrange
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                TipRow("Make sure $receiverName uses the exact phone number you entered when signing in.")
                Spacer(modifier = Modifier.height(8.dp))
                TipRow("If they don't see the text, check that the phone number is correct and try re-sending the invite.")
                Spacer(modifier = Modifier.height(8.dp))
                TipRow("The app will automatically match them to your family — no codes or links to enter.")
                Spacer(modifier = Modifier.height(8.dp))
                TipRow("You can adjust the check-in schedule anytime from the Family tab.")
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        TextButton(
            onClick = onDone,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Done")
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

@Composable
private fun SetupStepRow(
    stepNumber: Int,
    icon: ImageVector,
    title: String,
    description: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.Start
    ) {
        // Step number circle
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(GuideGreen),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "$stepNumber",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
        }

        Spacer(modifier = Modifier.width(14.dp))

        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = GuideGreen
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun TipRow(text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top
    ) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = null,
            modifier = Modifier
                .size(14.dp)
                .padding(top = 2.dp),
            tint = TipOrange
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
