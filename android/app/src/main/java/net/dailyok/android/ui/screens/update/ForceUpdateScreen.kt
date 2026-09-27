package net.dailyok.android.ui.screens.update

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import net.dailyok.android.network.ForceUpdateState

/**
 * Blocking screen shown when the backend says this build is below
 * MIN_SUPPORTED_ANDROID_APP_VERSION (GET /app-config, or a 426 from an edge
 * call). No dismiss: the only way forward is the Play Store. Back leaves the
 * app rather than revealing the screens underneath.
 */
@Composable
fun ForceUpdateScreen(updateUrl: String) {
    val context = LocalContext.current
    BackHandler { (context as? android.app.Activity)?.moveTaskToBack(true) }

    fun openStore() {
        // Prefer the Play Store app (market://), then the web URL we were given.
        val packageName = context.packageName
        val attempts = listOf(
            Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
                .setPackage("com.android.vending"),
            Intent(Intent.ACTION_VIEW, Uri.parse(updateUrl.ifBlank { ForceUpdateState.DEFAULT_UPDATE_URL })),
        )
        for (intent in attempts) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (_: ActivityNotFoundException) {
                // try the next one
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "Update Daily OK",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onBackground,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() }
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "This version of Daily OK is no longer supported. Please update to the latest version to keep your family's check-ins working.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 480.dp)
        )
        Spacer(modifier = Modifier.height(24.dp))
        Button(
            onClick = { openStore() },
            modifier = Modifier
                .widthIn(max = 360.dp)
                .fillMaxWidth()
                .height(52.dp)
        ) {
            Text("Update now", fontWeight = FontWeight.SemiBold)
        }
    }
}
