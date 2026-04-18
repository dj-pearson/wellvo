package net.dailyok.android.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import net.dailyok.android.ui.theme.DailyOKElevation
import net.dailyok.android.ui.theme.DailyOKGlass
import net.dailyok.android.ui.theme.DailyOKGlassStyle
import net.dailyok.android.ui.theme.glassSurface

/**
 * Branded glass bottom sheet: translucent container with a gentle brand tint
 * that catches the ambient gradient behind it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlassBottomSheet(
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    sheetState: SheetState = rememberModalBottomSheetState(),
    style: DailyOKGlassStyle = DailyOKGlassStyle.Regular,
    content: @Composable () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = sheetState,
        containerColor = Color.Transparent,
        scrimColor = Color.Black.copy(alpha = 0.35f),
        dragHandle = null,
        modifier = modifier
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .glassSurface(
                    style = style,
                    shape = RoundedCornerShape(
                        topStart = DailyOKGlass.RadiusXL,
                        topEnd = DailyOKGlass.RadiusXL,
                        bottomStart = 0.dp,
                        bottomEnd = 0.dp
                    ),
                    elevation = DailyOKElevation.level5
                )
                .padding(top = 8.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 16.dp)
            ) {
                content()
            }
            // Branded drag indicator
            Box(
                modifier = Modifier
                    .padding(top = 8.dp)
                    .fillMaxWidth(),
                contentAlignment = androidx.compose.ui.Alignment.TopCenter
            ) {
                Box(
                    modifier = Modifier
                        .padding(top = 0.dp)
                        .then(
                            Modifier.then(
                                Modifier.padding(horizontal = 0.dp)
                            )
                        )
                        .then(Modifier)
                )
            }
        }
    }
}

/**
 * Branded glass-styled AlertDialog wrapper. Uses Material3 AlertDialog but
 * overrides containerColor for consistency with the glass language.
 */
@Composable
fun GlassAlertDialog(
    onDismissRequest: () -> Unit,
    title: @Composable () -> Unit,
    text: @Composable () -> Unit,
    confirmButton: @Composable () -> Unit,
    dismissButton: @Composable (() -> Unit)? = null,
    properties: DialogProperties = DialogProperties()
) {
    AlertDialog(
        onDismissRequest = onDismissRequest,
        title = title,
        text = text,
        confirmButton = confirmButton,
        dismissButton = dismissButton,
        shape = RoundedCornerShape(DailyOKGlass.RadiusLarge),
        containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
        properties = properties
    )
}
