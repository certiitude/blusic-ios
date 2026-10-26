package app.blusic.android

import android.content.Context
import org.json.JSONObject

data class BundledRelay(val address: String, val access: String, val revision: String) {
    fun shouldInstall(state: LibraryState, savedAccess: String?, force: Boolean = false): Boolean = force ||
        (!state.relayDisabled && (state.relayAddress.isBlank() || state.relayAddress.trimEnd('/') == address) &&
            (state.relayRevision != revision || state.relayAddress.isBlank() || savedAccess != access))
    companion object {
        fun parse(text: String): BundledRelay {
            val j = JSONObject(text); val address = MusicApi.validateInstance(j.getString("url"))
            require(address == "https://blusic-audio-relay.onrender.com" && j.getLong("expiresAt") == 0L)
            val access = j.getString("access"); require(access.matches(Regex("app\\.android\\.[a-f0-9]{64}")))
            return BundledRelay(address, access, j.getString("revision").also { require(it.isNotBlank()) })
        }
        fun load(context: Context): BundledRelay? = runCatching { parse(context.assets.open("bundled-relay.json").bufferedReader().use { it.readText() }) }.getOrNull()
    }
}
