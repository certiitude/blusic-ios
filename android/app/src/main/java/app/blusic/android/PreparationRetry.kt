package app.blusic.android

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive

object PreparationRetry {
    fun waitMillis(failures: Int): Long = minOf(10_000L, 1000L shl (failures - 1).coerceIn(0, 4))
    suspend fun <T> run(operation: suspend () -> T, onRetry: suspend (Int, Long) -> Unit = { _, _ -> }, pause: suspend (Long) -> Unit = { delay(it) }): T {
        var failures = 0
        while (true) {
            currentCoroutineContext().ensureActive()
            try { return operation() }
            catch (e: Exception) {
                currentCoroutineContext().ensureActive()
                failures = (failures + 1).coerceAtMost(1_000_000)
                val wait = waitMillis(failures)
                onRetry(failures, wait)
                pause(wait)
            }
        }
    }
}
