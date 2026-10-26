package app.blusic.android

import java.net.URI
import kotlin.math.ceil

/** Upgrade only documented thumbnail sizing, never arbitrary signed URLs. */
object ArtworkPolicy {
    fun pixels(dp: Float, density: Float): Int = ceil(dp.coerceAtLeast(1f) * density).toInt().coerceIn(64, 1536)
    fun candidates(address: String, pixels: Int): List<String> {
        val uri = runCatching { URI(address) }.getOrNull() ?: return listOf(address)
        val host = uri.host?.lowercase().orEmpty(); val target = pixels.coerceIn(64, 1536)
        if (uri.scheme != "https" || uri.rawQuery != null || uri.rawFragment != null || uri.userInfo != null) return listOf(address)
        if (host.endsWith(".googleusercontent.com") || host == "yt3.ggpht.com") {
            val marker = address.lastIndexOf('=')
            if (marker > address.indexOf('/', 8) && address.substring(marker + 1).matches(Regex("[whs][0-9]+(?:-[A-Za-z0-9]+)*"))) {
                return listOf(address.substring(0, marker) + "=w$target-h$target-l90-rj", address).distinct()
            }
        }
        if (host in listOf("i.ytimg.com", "img.youtube.com")) {
            val path = uri.path
            if (Regex("/(vi|vi_webp)/[A-Za-z0-9_-]{11}/(default|mqdefault|hqdefault|sddefault|maxresdefault)\\.(jpg|webp)").matches(path)) {
                val directory = address.substringBeforeLast('/')
                val extension = address.substringAfterLast('.')
                return (if (target > 480) listOf("$directory/maxresdefault.$extension", "$directory/hqdefault.$extension", address) else listOf("$directory/hqdefault.$extension", address)).distinct()
            }
        }
        return listOf(address)
    }
}
