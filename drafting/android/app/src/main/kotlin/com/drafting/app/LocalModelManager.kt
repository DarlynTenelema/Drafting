package com.drafting.app

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlin.concurrent.thread

/**
 * Tarea 3.1 — Gestor de descarga On-Demand del modelo GGUF cuantizado (Q4_K_M).
 * Mantiene el APK liviano: el usuario descarga el archivo una sola vez desde CDN/HuggingFace,
 * verifica SHA-256 y puede borrarlo en cualquier momento para liberar espacio.
 */
object LocalModelManager {

    const val MODEL_FILENAME = "drafting_wr_local_v1_q4_k_m.gguf"
    const val MODEL_DISPLAY_NAME = "Drafting Local v1 (Q4_K_M)"

    // Enlace directo "resolve/main" del repositorio público en Hugging Face
    @Volatile
    var defaultModelUrl: String =
        "https://huggingface.co/DarlynTenelema/drafting-wr-local-v1/resolve/main/drafting_wr_local_v1_q4_k_m.gguf"

    @Volatile
    var defaultExpectedSha256: String = "32806fcfb886a797b8f45c30206cf46c09c969aea03e3e8e57d75cfae5f6ab88"

    @Volatile
    var isDownloading: Boolean = false
        private set

    fun getModelDir(context: Context): File {
        val dir = File(context.filesDir, "local_ai")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun getModelFile(context: Context): File = File(getModelDir(context), MODEL_FILENAME)

    fun isModelDownloaded(context: Context): Boolean {
        val f = getModelFile(context)
        return f.exists() && f.length() > 10 * 1024 * 1024L // > 10 MB
    }

    fun getStatus(context: Context): Map<String, Any> {
        val f = getModelFile(context)
        val downloaded = isModelDownloaded(context)
        val sizeMb = if (downloaded) f.length() / (1024.0 * 1024.0) else 0.0
        return mapOf(
            "isDownloaded" to downloaded,
            "isDownloading" to isDownloading,
            "sizeMb" to Math.round(sizeMb * 10.0) / 10.0,
            "modelName" to MODEL_DISPLAY_NAME,
            "modelPath" to if (downloaded) f.absolutePath else ""
        )
    }

    fun deleteModel(context: Context): Boolean {
        LocalLlmEngine.releaseModel()
        val f = getModelFile(context)
        val part = File(getModelDir(context), "$MODEL_FILENAME.part")
        if (part.exists()) part.delete()
        return if (f.exists()) f.delete() else true
    }

    fun downloadModelAsync(
        context: Context,
        customUrl: String? = null,
        expectedSha256: String? = null,
        onProgress: (Int) -> Unit,
        onComplete: (Boolean, String) -> Unit
    ) {
        if (isDownloading) {
            onComplete(false, "Ya hay una descarga en curso.")
            return
        }
        val urlStr = (customUrl?.takeIf { it.isNotBlank() } ?: defaultModelUrl).trim()
        if (urlStr.isEmpty()) {
            onComplete(false, "URL del modelo GGUF aún no configurada.")
            return
        }
        val shaTarget = (expectedSha256?.takeIf { it.isNotBlank() } ?: defaultExpectedSha256).trim().lowercase()

        isDownloading = true
        thread(name = "LocalModelDownloader") {
            var conn: HttpURLConnection? = null
            val partFile = File(getModelDir(context), "$MODEL_FILENAME.part")
            val finalFile = getModelFile(context)
            try {
                // Seguir redirecciones manualmente (301/302/303/307/308, usado por Hugging Face / Xet CDN)
                var currentUrl = urlStr
                var hops = 0
                while (true) {
                    conn = (URL(currentUrl).openConnection() as HttpURLConnection).apply {
                        requestMethod = "GET"
                        connectTimeout = 20_000
                        readTimeout = 60_000
                        instanceFollowRedirects = false
                        setRequestProperty("User-Agent", "DraftingAndroid/1.0")
                    }
                    val code = conn.responseCode
                    if (code in listOf(301, 302, 303, 307, 308)) {
                        val location = conn.getHeaderField("Location")
                            ?: throw IllegalStateException("Redirección sin Location (HTTP $code)")
                        conn.disconnect()
                        currentUrl = URL(URL(currentUrl), location).toString()
                        hops++
                        if (hops > 6) throw IllegalStateException("Demasiadas redirecciones al descargar modelo")
                        continue
                    }
                    if (code !in 200..299) {
                        throw IllegalStateException("HTTP $code al descargar modelo")
                    }
                    break
                }
                val activeConn = conn ?: throw IllegalStateException("Conexión nula al descargar modelo")
                val totalBytes = activeConn.contentLengthLong
                val digest = MessageDigest.getInstance("SHA-256")
                var downloadedBytes = 0L
                var lastPct = -1

                activeConn.inputStream.use { input ->
                    FileOutputStream(partFile).use { out ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val read = input.read(buf)
                            if (read <= 0) break
                            out.write(buf, 0, read)
                            digest.update(buf, 0, read)
                            downloadedBytes += read
                            if (totalBytes > 0) {
                                val pct = ((downloadedBytes * 100L) / totalBytes).toInt().coerceIn(0, 100)
                                if (pct != lastPct) {
                                    lastPct = pct
                                    onProgress(pct)
                                }
                            }
                        }
                    }
                }

                if (shaTarget.isNotEmpty()) {
                    val actualSha = digest.digest().joinToString("") { "%02x".format(it) }
                    if (actualSha != shaTarget) {
                        partFile.delete()
                        throw SecurityException("Verificación SHA-256 fallida")
                    }
                }

                if (finalFile.exists()) finalFile.delete()
                if (!partFile.renameTo(finalFile)) {
                    throw IllegalStateException("No se pudo guardar el archivo del modelo")
                }
                onProgress(100)
                onComplete(true, finalFile.absolutePath)
            } catch (e: Exception) {
                partFile.delete()
                onComplete(false, e.message ?: "Error descargando modelo local")
            } finally {
                conn?.disconnect()
                isDownloading = false
            }
        }
    }
}
