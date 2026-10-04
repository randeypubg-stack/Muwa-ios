package app.muwa.nasheeds

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.io.IOException
import java.security.KeyStore
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

// Keep the continuation pending until the body is consumed so cancellation also
// closes a stalled download/upload, not only the wait for response headers.
internal suspend fun <T> Call.awaitResult(read: (Response) -> T): T = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, error: IOException) { continuation.resumeWithException(error) }
        override fun onResponse(call: Call, response: Response) {
            runCatching { response.use(read) }.fold(
                onSuccess = { continuation.resume(it) },
                onFailure = { continuation.resumeWithException(it) }
            )
        }
    })
}

private class SessionCookies(context: Context) : CookieJar {
    private val file = File(context.filesDir, "session.bin")
    private var cookies = mutableListOf<Cookie>()
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("muwa.session", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("muwa.session", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    init {
        runCatching {
            val data = file.readBytes(); val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(0, 12)))
            val saved = JSONArray(String(cipher.doFinal(data.copyOfRange(12, data.size))))
            for (i in 0 until saved.length()) Cookie.parse(Backend.url, saved.getString(i))?.let { cookies.add(it) }
        }
    }
    @Synchronized override fun saveFromResponse(url: HttpUrl, values: List<Cookie>) {
        values.forEach { cookie -> cookies.removeAll { it.name == cookie.name && it.domain == cookie.domain && it.path == cookie.path }; cookies.add(cookie) }
        cookies.removeAll { it.expiresAt < System.currentTimeMillis() }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        runCatching {
            file.writeBytes(cipher.iv + cipher.doFinal(JSONArray(cookies.map { it.toString() }).toString().toByteArray()))
        }.onFailure { Diagnostics.record("session-storage", it) }
    }
    @Synchronized override fun loadForRequest(url: HttpUrl): List<Cookie> = cookies.filter { it.expiresAt >= System.currentTimeMillis() && it.matches(url) }
    @Synchronized fun clear() { cookies.clear(); file.delete() }
}
class Backend(context: Context) {
    companion object {
        const val base = "https://93.188.187.96"
        val url = okhttp3.HttpUrl.Builder().scheme("https").host("93.188.187.96").build()
    }
    private val cookies = SessionCookies(context)
    private val client = OkHttpClient.Builder().cookieJar(cookies).connectTimeout(20, TimeUnit.SECONDS).readTimeout(45, TimeUnit.SECONDS).build()
    internal val mediaClient = client.newBuilder().readTimeout(60, TimeUnit.SECONDS).build()
    private val uploads = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(300, TimeUnit.SECONDS).writeTimeout(300, TimeUnit.SECONDS).build()
    suspend fun request(path: String, body: JSONObject? = null, envelope: Boolean = false): JSONObject = withContext(Dispatchers.IO) {
        val builder = Request.Builder().url("$base/_api/$path").header("Accept", "application/json")
        if (body != null) builder.post((if (envelope) JSONObject().put("json", body) else body).toString().toRequestBody("application/json".toMediaType()))
        client.newCall(builder.build()).awaitResult { response ->
            val text = response.body?.string().orEmpty()
            val raw = runCatching { JSONObject(text) }.getOrElse { throw IllegalStateException("Сервер вернул неверный ответ (${response.code}).") }
            val data = raw.optJSONObject("json") ?: raw
            if (!response.isSuccessful) throw ApiException(response.code, data.optString("error", data.optString("message", "Сервис недоступен. Повторите позже.")))
            data
        }
    }
    fun clearSession() { cookies.clear() }
    suspend fun put(url: String, file: File, mime: String, headers: JSONObject? = null) = withContext(Dispatchers.IO) {
        require(url.startsWith("https://"))
        val request = Request.Builder().url(url)
        headers?.keys()?.forEach { name -> request.header(name, headers.getString(name)) }
        uploads.newCall(request.put(object : RequestBody() {
            override fun contentType() = mime.toMediaType()
            override fun contentLength() = file.length()
            override fun writeTo(sink: okio.BufferedSink) { file.inputStream().use { input -> val bytes = ByteArray(64 * 1024); var count: Int; while (input.read(bytes).also { count = it } != -1) sink.write(bytes, 0, count) } }
        }).build()).awaitResult { check(it.isSuccessful) { "Не удалось загрузить файл (${it.code})." } }
    }
}
class ApiException(val status: Int, message: String) : Exception(message)
