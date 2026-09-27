package net.dailyok.android.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.HttpURLConnection
import java.net.URI

/** Body of GET <edge>/app-config (edge-functions/shared/config.ts appConfigPayload). */
@Serializable
data class AppConfig(
    @SerialName("min_ios_version") val minIosVersion: String? = null,
    @SerialName("min_android_version") val minAndroidVersion: String? = null,
    @SerialName("update_url_ios") val updateUrlIos: String? = null,
    @SerialName("update_url_android") val updateUrlAndroid: String? = null
)

/**
 * App-wide "this build is too old" state (CLAUDE.md MIN_SUPPORTED_ANDROID_APP_VERSION).
 * While [required] is true the app shows only the blocking update screen.
 *
 * Two ways in, matching iOS ForceUpdateState:
 * - [refreshFromServer] reads GET /app-config at launch and on every resume
 *   (throttled). Most of the app talks to PostgREST directly, so a retired
 *   build might otherwise never make an edge call that could answer 426.
 * - ApiService latches it on any 426 `update_required`. A 426 is never undone
 *   in-process; a later /app-config at or above the floor clears only an
 *   /app-config block (an operator lowering a floor raised by mistake).
 */
object ForceUpdateState {
    const val DEFAULT_UPDATE_URL = "https://play.google.com/store/apps/details?id=net.dailyok.android"
    private const val CHECK_INTERVAL_MS = 5 * 60 * 1000L

    private val json = Json { ignoreUnknownKeys = true }

    private val _required = MutableStateFlow(false)
    val required: StateFlow<Boolean> = _required.asStateFlow()

    private val _updateUrl = MutableStateFlow(DEFAULT_UPDATE_URL)
    val updateUrl: StateFlow<String> = _updateUrl.asStateFlow()

    @Volatile private var latchedByServerRejection = false
    @Volatile private var lastCheckAt = 0L

    /** A 426 from an edge endpoint; [body] is its JSON (update_url is read if present). */
    fun triggerFromResponse(body: String?) {
        val url = body?.let {
            runCatching { json.parseToJsonElement(it).jsonObject["update_url"]?.jsonPrimitive?.contentOrNull }
                .getOrNull()
        }
        latchedByServerRejection = true
        apply(true, url)
    }

    /**
     * Ask the server for the floor and block if [appVersion] is below it.
     * Fails open: offline, a 404 from a server without the route, or an
     * unreadable body leave the app running (the 426 path still backs it up).
     */
    suspend fun refreshFromServer(edgeFunctionsUrl: String, appVersion: String, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastCheckAt < CHECK_INTERVAL_MS) return
        lastCheckAt = now
        val config = fetch(edgeFunctionsUrl, appVersion) ?: return
        if (isBelowMinimum(appVersion, config.minAndroidVersion)) {
            apply(true, config.updateUrlAndroid)
        } else if (!latchedByServerRejection) {
            apply(false, config.updateUrlAndroid)
        }
    }

    private fun apply(required: Boolean, url: String?) {
        if (!url.isNullOrBlank() && url.startsWith("https://")) _updateUrl.value = url
        _required.value = required
    }

    private suspend fun fetch(edgeFunctionsUrl: String, appVersion: String): AppConfig? =
        withContext(Dispatchers.IO) {
            val base = edgeFunctionsUrl.trimEnd('/')
            if (base.isBlank()) return@withContext null
            var connection: HttpURLConnection? = null
            try {
                connection = (URI.create("$base/app-config").toURL().openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    setRequestProperty("X-App-Version", appVersion)
                    setRequestProperty("X-App-Platform", "android")
                    setRequestProperty("Accept", "application/json")
                }
                if (connection.responseCode != 200) return@withContext null
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                json.decodeFromString<AppConfig>(body)
            } catch (_: Exception) {
                null
            } finally {
                connection?.disconnect()
            }
        }

    /**
     * Dotted numeric compare, the same rules as the server's compareVersions:
     * missing segments are 0 ("1.0" == "1.0.0"), a non-numeric segment is 0.
     * Negative when a < b.
     */
    fun compareVersions(a: String, b: String): Int {
        val pa = a.split(".")
        val pb = b.split(".")
        for (i in 0 until maxOf(pa.size, pb.size)) {
            val na = pa.getOrNull(i)?.trim()?.let { seg -> seg.takeWhile { it.isDigit() }.toIntOrNull() } ?: 0
            val nb = pb.getOrNull(i)?.trim()?.let { seg -> seg.takeWhile { it.isDigit() }.toIntOrNull() } ?: 0
            if (na != nb) return na.compareTo(nb)
        }
        return 0
    }

    /** True only for a real floor ("0.0.0", blank or null means none) that [current] is below. */
    fun isBelowMinimum(current: String, minimum: String?): Boolean {
        val floor = minimum?.trim().orEmpty()
        if (floor.isEmpty() || compareVersions(floor, "0.0.0") <= 0) return false
        return compareVersions(current.trim(), floor) < 0
    }
}
