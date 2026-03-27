package net.wellvo.android.network

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

suspend fun <T> withRetry(
    maxAttempts: Int = 3,
    initialDelayMs: Long = 1000L,
    block: suspend () -> T
): T {
    var lastException: Exception? = null
    var currentDelay = initialDelayMs

    repeat(maxAttempts) { attempt ->
        try {
            return block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: WellvoError.Auth) {
            throw e
        } catch (e: Exception) {
            lastException = e
            if (attempt < maxAttempts - 1) {
                delay(currentDelay)
                currentDelay *= 2
            }
        }
    }

    throw lastException ?: WellvoError.Unknown()
}
