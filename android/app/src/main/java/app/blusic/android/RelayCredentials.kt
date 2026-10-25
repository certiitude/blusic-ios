package app.blusic.android

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Only ciphertext is stored in preferences; the AES key stays in Android Keystore. */
class RelayCredentials(context: Context) {
    private val prefs = context.getSharedPreferences("relay_credentials", Context.MODE_PRIVATE)
    @Synchronized private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = "blusic-relay-key"
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun save(value: String, server: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()); updateAAD(server.toByteArray()) }
        val encrypted = cipher.iv + cipher.doFinal(value.toByteArray())
        check(prefs.edit().putString(server, Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit())
    }
    fun read(server: String): String? = runCatching {
        val bytes = Base64.decode(prefs.getString(server, null) ?: return null, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))); updateAAD(server.toByteArray()) }
        String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)))
    }.getOrNull()
}
