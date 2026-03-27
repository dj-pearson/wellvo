package net.wellvo.android.services

import android.app.Activity
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import net.wellvo.android.network.ApiService
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

enum class SubscriptionTier {
    Free, Family, FamilyPlus
}

sealed class BillingError(message: String) : Exception(message) {
    class NotConnected : BillingError("Billing client not connected")
    class UserCancelled : BillingError("Purchase cancelled")
    class AlreadyOwned : BillingError("You already own this subscription")
    class NetworkError : BillingError("Network error during purchase")
    class Unknown(msg: String) : BillingError(msg)
}

@Singleton
class SubscriptionService @Inject constructor(
    private val apiService: ApiService
) : PurchasesUpdatedListener {

    companion object {
        private const val TAG = "SubscriptionService"

        val PRODUCT_IDS = listOf(
            "net.wellvo.family.monthly",
            "net.wellvo.family.yearly",
            "net.wellvo.familyplus.monthly",
            "net.wellvo.familyplus.yearly",
            "net.wellvo.addon.receiver",
            "net.wellvo.addon.viewer"
        )
    }

    private var billingClient: BillingClient? = null
    private var pendingPurchaseCallback: ((Result<Purchase>) -> Unit)? = null

    private val _products = MutableStateFlow<List<ProductDetails>>(emptyList())
    val products: StateFlow<List<ProductDetails>> = _products.asStateFlow()

    private val _currentTier = MutableStateFlow(SubscriptionTier.Free)
    val currentTier: StateFlow<SubscriptionTier> = _currentTier.asStateFlow()

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    fun initialize(activity: Activity) {
        if (billingClient?.isReady == true) return

        billingClient = BillingClient.newBuilder(activity)
            .setListener(this)
            .enablePendingPurchases()
            .build()

        billingClient?.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                    Log.d(TAG, "Billing client connected")
                    _isConnected.value = true
                } else {
                    Log.e(TAG, "Billing setup failed: ${billingResult.debugMessage}")
                    _isConnected.value = false
                }
            }

            override fun onBillingServiceDisconnected() {
                Log.w(TAG, "Billing service disconnected")
                _isConnected.value = false
            }
        })
    }

    suspend fun loadProducts() {
        val client = billingClient ?: throw BillingError.NotConnected()
        if (!client.isReady) throw BillingError.NotConnected()

        val productList = PRODUCT_IDS.map { productId ->
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(productId)
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        }

        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(productList)
            .build()

        val result = client.queryProductDetails(params)
        if (result.billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
            _products.value = result.productDetailsList ?: emptyList()
            Log.d(TAG, "Loaded ${_products.value.size} products")
        } else {
            Log.e(TAG, "Failed to load products: ${result.billingResult.debugMessage}")
        }
    }

    suspend fun purchase(activity: Activity, productDetails: ProductDetails, offerToken: String): Purchase {
        val client = billingClient ?: throw BillingError.NotConnected()
        if (!client.isReady) throw BillingError.NotConnected()

        val productDetailsParamsList = listOf(
            BillingFlowParams.ProductDetailsParams.newBuilder()
                .setProductDetails(productDetails)
                .setOfferToken(offerToken)
                .build()
        )

        val flowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(productDetailsParamsList)
            .build()

        return suspendCancellableCoroutine { continuation ->
            pendingPurchaseCallback = { result ->
                result.fold(
                    onSuccess = { continuation.resume(it) },
                    onFailure = { continuation.resume(throw it) }
                )
            }

            val launchResult = client.launchBillingFlow(activity, flowParams)
            if (launchResult.responseCode != BillingClient.BillingResponseCode.OK) {
                pendingPurchaseCallback = null
                continuation.resume(throw BillingError.Unknown(
                    "Launch billing flow failed: ${launchResult.debugMessage}"
                ))
            }
        }
    }

    override fun onPurchasesUpdated(billingResult: BillingResult, purchases: MutableList<Purchase>?) {
        when (billingResult.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val purchase = purchases?.firstOrNull()
                if (purchase != null) {
                    pendingPurchaseCallback?.invoke(Result.success(purchase))
                    pendingPurchaseCallback = null
                    // Process purchase asynchronously
                    kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
                        processPurchase(purchase)
                    }
                }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                pendingPurchaseCallback?.invoke(Result.failure(BillingError.UserCancelled()))
                pendingPurchaseCallback = null
            }
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                pendingPurchaseCallback?.invoke(Result.failure(BillingError.AlreadyOwned()))
                pendingPurchaseCallback = null
            }
            BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE,
            BillingClient.BillingResponseCode.SERVICE_DISCONNECTED -> {
                pendingPurchaseCallback?.invoke(Result.failure(BillingError.NetworkError()))
                pendingPurchaseCallback = null
            }
            else -> {
                pendingPurchaseCallback?.invoke(
                    Result.failure(BillingError.Unknown(billingResult.debugMessage ?: "Purchase failed"))
                )
                pendingPurchaseCallback = null
            }
        }
    }

    private suspend fun processPurchase(purchase: Purchase) {
        // Acknowledge if not yet acknowledged
        if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED && !purchase.isAcknowledged) {
            try {
                val acknowledgeParams = AcknowledgePurchaseParams.newBuilder()
                    .setPurchaseToken(purchase.purchaseToken)
                    .build()
                val result = billingClient?.acknowledgePurchase(acknowledgeParams)
                if (result?.responseCode == BillingClient.BillingResponseCode.OK) {
                    Log.d(TAG, "Purchase acknowledged")
                } else {
                    Log.e(TAG, "Failed to acknowledge purchase: ${result?.debugMessage}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error acknowledging purchase", e)
            }
        }

        // Verify server-side
        try {
            val payload = buildJsonObject {
                put("purchase_token", purchase.purchaseToken)
                put("product_id", purchase.products.firstOrNull() ?: "")
                put("platform", "android")
                put("order_id", purchase.orderId ?: "")
            }
            apiService.subscriptionWebhook(payload)
            Log.d(TAG, "Purchase verified server-side")
            updateCurrentTier()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to verify purchase server-side", e)
        }
    }

    suspend fun restorePurchases() {
        val client = billingClient ?: throw BillingError.NotConnected()
        if (!client.isReady) throw BillingError.NotConnected()

        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()

        val result = client.queryPurchasesAsync(params)
        if (result.billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
            val activePurchases = result.purchasesList.filter {
                it.purchaseState == Purchase.PurchaseState.PURCHASED
            }
            Log.d(TAG, "Restored ${activePurchases.size} active purchases")

            for (purchase in activePurchases) {
                processPurchase(purchase)
            }
            updateCurrentTier()
        } else {
            Log.e(TAG, "Failed to restore purchases: ${result.billingResult.debugMessage}")
        }
    }

    fun hasAccess(tier: SubscriptionTier): Boolean {
        return when (tier) {
            SubscriptionTier.Free -> true
            SubscriptionTier.Family -> _currentTier.value == SubscriptionTier.Family || _currentTier.value == SubscriptionTier.FamilyPlus
            SubscriptionTier.FamilyPlus -> _currentTier.value == SubscriptionTier.FamilyPlus
        }
    }

    fun currentTier(): SubscriptionTier = _currentTier.value

    private suspend fun updateCurrentTier() {
        val client = billingClient ?: return
        if (!client.isReady) return

        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()

        val result = client.queryPurchasesAsync(params)
        if (result.billingResult.responseCode != BillingClient.BillingResponseCode.OK) return

        val activeProductIds = result.purchasesList
            .filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }
            .flatMap { it.products }
            .toSet()

        _currentTier.value = when {
            activeProductIds.any { it.startsWith("net.wellvo.familyplus") } -> SubscriptionTier.FamilyPlus
            activeProductIds.any { it.startsWith("net.wellvo.family") } -> SubscriptionTier.Family
            else -> SubscriptionTier.Free
        }

        Log.d(TAG, "Current tier: ${_currentTier.value}")
    }

    fun destroy() {
        billingClient?.endConnection()
        billingClient = null
        _isConnected.value = false
    }
}
