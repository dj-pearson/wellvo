package net.dailyok.android.ui.screens.owner

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import net.dailyok.android.BuildConfig
import net.dailyok.android.R
import net.dailyok.android.services.BillingError
import net.dailyok.android.services.SubscriptionService
import net.dailyok.android.services.SubscriptionTier

private val paywallFeatures = listOf(
    net.dailyok.android.ui.components.PaywallFeature(
        icon = Icons.Default.Group,
        title = "Unlimited family members",
        description = "Add every parent, sibling, and caregiver — everyone stays in the loop."
    ),
    net.dailyok.android.ui.components.PaywallFeature(
        icon = Icons.Default.NotificationsActive,
        title = "Smart escalation alerts",
        description = "If a check-in is missed, the right person hears about it right away."
    ),
    net.dailyok.android.ui.components.PaywallFeature(
        icon = Icons.Default.BarChart,
        title = "Pattern insights",
        description = "Spot mood and timing trends across the family at a glance."
    ),
    net.dailyok.android.ui.components.PaywallFeature(
        icon = Icons.Default.CloudDone,
        title = "Long-term history",
        description = "Keep a full archive of check-ins for context and peace of mind."
    ),
    net.dailyok.android.ui.components.PaywallFeature(
        icon = Icons.Default.Shield,
        title = "Privacy-first by design",
        description = "End-to-end encryption and rigorous data minimization — always."
    )
)

private val paywallTestimonial = net.dailyok.android.ui.components.Testimonial(
    quote = "Daily OK gives me peace of mind every morning. It's the first app I check.",
    author = "Sarah M., parent of two"
)

private data class PlanInfo(
    val tier: SubscriptionTier,
    val name: String,
    val monthlyPrice: String,
    val yearlyPrice: String,
    val features: List<String>
)

private val plans = listOf(
    PlanInfo(
        tier = SubscriptionTier.Caregiver,
        name = "Caregiver",
        monthlyPrice = "$3.99/mo",
        yearlyPrice = "$29.99/yr",
        features = listOf(
            "1 Receiver",
            "Up to 3 Viewers",
            "Daily + on-demand check-ins",
            "Full escalation chain",
            "Mood tracking",
            "Pattern alerts",
            "90-day history"
        )
    ),
    PlanInfo(
        tier = SubscriptionTier.Family,
        name = "Family",
        monthlyPrice = "$6.99/mo",
        yearlyPrice = "$49.99/yr",
        features = listOf(
            "Up to 3 Receivers",
            "Up to 5 Viewers",
            "Everything in Caregiver",
            "Clinician PDF export",
            "1-year history",
            "Kid mode"
        )
    ),
    PlanInfo(
        tier = SubscriptionTier.FamilyPlus,
        name = "Family+",
        monthlyPrice = "$9.99/mo",
        yearlyPrice = "$79.99/yr",
        features = listOf(
            "Up to 6 Receivers",
            "Up to 10 Viewers",
            "Everything in Family",
            "Critical Alerts (bypass DND)",
            "Unlimited history",
            "Priority support"
        )
    )
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscriptionScreen(
    subscriptionService: SubscriptionService,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val activity = context as? Activity
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val currentTier by subscriptionService.currentTier.collectAsState()
    val products by subscriptionService.products.collectAsState()
    var isYearly by remember { mutableStateOf(false) }
    var isPurchasing by remember { mutableStateOf(false) }
    var isRestoring by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        activity?.let { subscriptionService.initialize(it) }
        try {
            subscriptionService.loadProducts()
        } catch (_: Exception) { }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Choose Your Plan") },
                colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent
                )
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = Color.Transparent
    ) { innerPadding ->
        Box(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
        net.dailyok.android.ui.components.AmbientBackground(
            tone = net.dailyok.android.ui.components.AmbientTone.Warm
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Premium feature carousel + social proof
            net.dailyok.android.ui.components.PaywallFeatureCarousel(
                features = paywallFeatures
            )

            net.dailyok.android.ui.components.TestimonialCard(
                testimonial = paywallTestimonial
            )

            // Monthly/Yearly toggle
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                FilterChip(
                    selected = !isYearly,
                    onClick = { isYearly = false },
                    label = { Text("Monthly") }
                )
                Spacer(modifier = Modifier.width(8.dp))
                FilterChip(
                    selected = isYearly,
                    onClick = { isYearly = true },
                    label = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Yearly")
                            Spacer(modifier = Modifier.width(8.dp))
                            net.dailyok.android.ui.components.AnnualSavingsBadge(percentSaved = 37)
                        }
                    }
                )
            }

            // Plan cards
            plans.forEach { plan ->
                val isCurrent = plan.tier == currentTier
                val accentColor = when (plan.tier) {
                    SubscriptionTier.Free -> MaterialTheme.colorScheme.outline
                    SubscriptionTier.Caregiver -> Color(0xFF2ECC71)
                    SubscriptionTier.Family -> Color(0xFF3B82F6)
                    SubscriptionTier.FamilyPlus -> Color(0xFFF97316)
                }

                net.dailyok.android.ui.components.GlassCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            if (isCurrent) Modifier.border(
                                BorderStroke(2.dp, accentColor),
                                androidx.compose.foundation.shape.RoundedCornerShape(
                                    net.dailyok.android.ui.theme.DailyOKGlass.RadiusLarge
                                )
                            ) else Modifier
                        ),
                    style = if (isCurrent) net.dailyok.android.ui.theme.DailyOKGlassStyle.Regular
                            else net.dailyok.android.ui.theme.DailyOKGlassStyle.Thin,
                    shape = androidx.compose.foundation.shape.RoundedCornerShape(
                        net.dailyok.android.ui.theme.DailyOKGlass.RadiusLarge
                    ),
                    elevation = if (isCurrent) net.dailyok.android.ui.theme.DailyOKElevation.level3
                                else net.dailyok.android.ui.theme.DailyOKElevation.level2,
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                if (plan.tier == SubscriptionTier.FamilyPlus) {
                                    Icon(
                                        Icons.Default.Star,
                                        contentDescription = null,
                                        modifier = Modifier.size(20.dp),
                                        tint = accentColor
                                    )
                                    Spacer(modifier = Modifier.width(4.dp))
                                }
                                Text(
                                    text = plan.name,
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = accentColor
                                )
                            }
                            if (isCurrent) {
                                Text(
                                    text = stringResource(R.string.plan_current),
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = accentColor
                                )
                            }
                        }

                        Spacer(modifier = Modifier.height(4.dp))

                        Text(
                            text = if (isYearly) plan.yearlyPrice else plan.monthlyPrice,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold
                        )

                        Spacer(modifier = Modifier.height(12.dp))

                        plan.features.forEach { feature ->
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.padding(vertical = 2.dp)
                            ) {
                                Icon(
                                    Icons.Default.Check,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                    tint = accentColor
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = feature,
                                    style = MaterialTheme.typography.bodySmall
                                )
                            }
                        }

                        if (!isCurrent && plan.tier != SubscriptionTier.Free) {
                            Spacer(modifier = Modifier.height(12.dp))
                            Button(
                                onClick = {
                                    if (activity == null) return@Button
                                    isPurchasing = true
                                    val productId = when {
                                        plan.tier == SubscriptionTier.Caregiver && !isYearly -> "net.dailyok.caregiver.monthly"
                                        plan.tier == SubscriptionTier.Caregiver && isYearly -> "net.dailyok.caregiver.yearly"
                                        plan.tier == SubscriptionTier.Family && !isYearly -> "net.dailyok.family.monthly"
                                        plan.tier == SubscriptionTier.Family && isYearly -> "net.dailyok.family.yearly"
                                        plan.tier == SubscriptionTier.FamilyPlus && !isYearly -> "net.dailyok.familyplus.monthly"
                                        plan.tier == SubscriptionTier.FamilyPlus && isYearly -> "net.dailyok.familyplus.yearly"
                                        else -> return@Button
                                    }
                                    scope.launch {
                                        try {
                                            val productDetails = products.find { it.productId == productId }
                                            if (productDetails == null) {
                                                snackbarHostState.showSnackbar("Product not available. Please try again.")
                                                return@launch
                                            }
                                            val offerToken = productDetails.subscriptionOfferDetails
                                                ?.firstOrNull()?.offerToken ?: ""
                                            subscriptionService.purchase(activity, productDetails, offerToken)
                                            snackbarHostState.showSnackbar("Welcome to ${plan.name}!")
                                        } catch (e: BillingError.UserCancelled) {
                                            // User cancelled, no message needed
                                        } catch (e: BillingError.AlreadyOwned) {
                                            snackbarHostState.showSnackbar("You already own this subscription.")
                                        } catch (e: Exception) {
                                            snackbarHostState.showSnackbar(e.message ?: "Purchase failed.")
                                        } finally {
                                            isPurchasing = false
                                        }
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                                enabled = !isPurchasing,
                                colors = ButtonDefaults.buttonColors(containerColor = accentColor),
                                shape = MaterialTheme.shapes.large
                            ) {
                                if (isPurchasing) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(18.dp),
                                        color = Color.White,
                                        strokeWidth = 2.dp
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                }
                                Text(
                                    text = if (currentTier.ordinal < plan.tier.ordinal) "Upgrade" else "Subscribe",
                                    color = Color.White
                                )
                            }
                        }
                    }
                }
            }

            // Manage subscription
            OutlinedButton(
                onClick = {
                    val intent = Intent(
                        Intent.ACTION_VIEW,
                        Uri.parse("https://play.google.com/store/account/subscriptions?package=${BuildConfig.APPLICATION_ID}")
                    )
                    context.startActivity(intent)
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.CreditCard, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Manage Subscription")
            }

            // Restore purchases
            OutlinedButton(
                onClick = {
                    isRestoring = true
                    scope.launch {
                        try {
                            subscriptionService.restorePurchases()
                            snackbarHostState.showSnackbar("Purchases restored.")
                        } catch (e: Exception) {
                            snackbarHostState.showSnackbar(e.message ?: "Failed to restore purchases.")
                        } finally {
                            isRestoring = false
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = !isRestoring
            ) {
                if (isRestoring) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.Default.Restore, contentDescription = null, modifier = Modifier.size(18.dp))
                }
                Spacer(modifier = Modifier.width(8.dp))
                Text("Restore Purchases")
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
        }
    }
}
