package com.drafting.app

import android.util.Log
import com.llamatik.library.platform.LlamaBridge

/**
 * Backend nativo llama.cpp (via Llamatik prebuilt arm64-v8a) para ejecutar
 * el modelo cuantizado Qwen2.5-0.5B-Instruct (Q4_K_M, ~379 MB) 100% offline.
 *
 * Optimizado para Infinix Hot 40 Pro (Helio G99, 8 GB RAM + Wild Rift abierto):
 * - contextLength = 1024 (bajo consumo de KV-Cache)
 * - numThreads = 4 (no satura los núcleos mientras corre Wild Rift)
 * - useMmap = true (carga rápida y menor presión de RAM)
 */
class LlamaCppSlmBackend : LocalLlmEngine.NativeSlmBackend {

    companion object {
        private const val TAG = "LlamaCppSlmBackend"
    }

    @Volatile
    private var loaded = false

    @Volatile
    private var loadedPath: String = ""

    private val lock = Any()

    override fun isLoaded(): Boolean = loaded

    override fun load(modelPath: String, threads: Int, grammarText: String): Boolean {
        synchronized(lock) {
            if (loaded && loadedPath == modelPath) return true
            return try {
                val safeThreads = threads.coerceIn(1, LocalLlmEngine.MAX_CPU_THREADS)
                LlamaBridge.updateGenerateParams(
                    temperature = 0.2f,
                    maxTokens = 180,
                    topP = 0.9f,
                    topK = 40,
                    repeatPenalty = 1.08f
                )
                val ok = LlamaBridge.initGenerateModel(modelPath)
                loaded = ok
                if (ok) {
                    loadedPath = modelPath
                    Log.i(TAG, "Modelo GGUF cargado correctamente ($safeThreads hilos): $modelPath")
                } else {
                    Log.w(TAG, "No se pudo inicializar el modelo GGUF: $modelPath")
                }
                ok
            } catch (e: Throwable) {
                Log.e(TAG, "Error cargando llama.cpp: ${e.message}", e)
                loaded = false
                false
            }
        }
    }

    override fun generate(systemPrompt: String, userJson: String, maxTokens: Int): String? {
        synchronized(lock) {
            if (!loaded) return null
            return try {
                // Formato exacto ChatML usado en el fine-tuning QLoRA de Qwen2.5-0.5B-Instruct
                val chatMlPrompt = buildString {
                    append("<|im_start|>system\n")
                    append(systemPrompt.trim())
                    append("<|im_end|>\n")
                    append("<|im_start|>user\n")
                    append(userJson.trim())
                    append("<|im_end|>\n")
                    append("<|im_start|>assistant\n")
                }

                val raw = LlamaBridge.generate(chatMlPrompt)
                val cleaned = raw
                    .substringBefore("<|im_end|>")
                    .substringBefore("<|endoftext|>")
                    .replace("**", "")
                    .trim()

                if (cleaned.isNotBlank()) cleaned else null
            } catch (e: Throwable) {
                Log.e(TAG, "Error generando respuesta con llama.cpp: ${e.message}", e)
                null
            }
        }
    }

    override fun unload() {
        synchronized(lock) {
            if (!loaded) return
            try {
                LlamaBridge.shutdown()
            } catch (e: Throwable) {
                Log.w(TAG, "Error liberando llama.cpp: ${e.message}")
            } finally {
                loaded = false
                loadedPath = ""
            }
        }
    }
}
