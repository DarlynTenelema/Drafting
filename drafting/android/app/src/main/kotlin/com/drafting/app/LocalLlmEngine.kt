package com.drafting.app

import android.app.ActivityManager
import android.content.Context
import android.util.Log

/**
 * Tarea 3.2 — Motor de Inferencia Local Híbrido para Android (Infinix Hot 40 Pro / Helio G99).
 *
 * Arquitectura en 2 etapas:
 *  1. DraftMathEngine (< 1 ms): Poda por rol + vectores de 143 campeones → Top 3 + runas verificadas.
 *  2. SLM Local GGUF (opcional, 4 hilos máx. + gramática GBNF): redacta la explicación natural.
 *     Si el .gguf aún no está descargado o hay poca RAM libre (< 1.2 GB con Wild Rift abierto),
 *     responde al instante con el renderizador matemático local (0% lag, 0% costo).
 */
object LocalLlmEngine {

    private const val TAG = "LocalLlmEngine"
    const val MAX_CPU_THREADS = 4
    private const val MIN_FREE_RAM_MB_FOR_SLM = 1100L

    data class LocalDraftResponse(
        val recommendation: String,
        val draftContext: String,
        val slmInputJson: String,
        val latencyMs: Double,
        val engineMode: String // "math_instant" | "math_plus_slm"
    )

    /**
     * Interfaz para conectar el runtime nativo llama.cpp JNI cuando carguemos el .gguf entrenado.
     */
    interface NativeSlmBackend {
        fun isLoaded(): Boolean
        fun load(modelPath: String, threads: Int, grammarText: String): Boolean
        fun generate(systemPrompt: String, userJson: String, maxTokens: Int): String?
        fun unload()
    }

    @Volatile
    var slmBackend: NativeSlmBackend? = LlamaCppSlmBackend()

    private const val SYSTEM_PROMPT =
        "Eres Drafting Local, analista táctico de Wild Rift. " +
            "Recibes un JSON con el estado del draft y el Top 3 calculado. " +
            "Responde SIN saludos ni asteriscos (**), de forma concisa (máx. 140 tokens), usando EXACTAMENTE este formato:\n" +
            "PLAN A: [Campeón 1]\n" +
            "• Por qué: [Razón táctica breve y directa]\n" +
            "• Runas: [Runas exactas del JSON]\n" +
            "• [Campeón 2]: [Por qué encaja en 1 línea]\n" +
            "• [Campeón 3]: [Por qué encaja en 1 línea]"

    fun hasEnoughRamForSlm(context: Context): Boolean {
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
            val memInfo = ActivityManager.MemoryInfo()
            am.getMemoryInfo(memInfo)
            val availMb = memInfo.availMem / (1024L * 1024L)
            !memInfo.lowMemory && availMb >= MIN_FREE_RAM_MB_FOR_SLM
        } catch (_: Exception) {
            false
        }
    }

    fun releaseModel() {
        try {
            slmBackend?.unload()
        } catch (e: Exception) {
            Log.w(TAG, "Error liberando modelo SLM: ${e.message}")
        }
    }

    fun analyzeDraftLocal(
        context: Context,
        role: String,
        bans: List<String> = emptyList(),
        allies: List<String> = emptyList(),
        enemies: List<String> = emptyList(),
        otp: String = "",
        myPick: String = "",
        draftPhase: String = "",
        exclude: List<String> = emptyList(),
        lang: String = "es"
    ): LocalDraftResponse {
        val t0 = System.nanoTime()

        // 1. Motor Matemático con poda por rol (< 1 ms, 0% alucinaciones)
        val mathRes = DraftMathEngine.recommend(
            context = context,
            role = role,
            bans = bans,
            allies = allies,
            enemies = enemies,
            otp = otp,
            myPick = myPick,
            draftPhase = draftPhase,
            exclude = exclude,
            lang = lang
        )
        val slmInput = mathRes.toSlmInputJson()
        val draftCtx = mathRes.toDraftContextJson()

        // 2. Si el GGUF está descargado, el backend JNI está activo y hay RAM segura, usar SLM
        val backend = slmBackend
        if (backend != null && LocalModelManager.isModelDownloaded(context) && hasEnoughRamForSlm(context)) {
            try {
                if (!backend.isLoaded()) {
                    val grammar = context.assets.open("draft_output.gbnf").bufferedReader().use { it.readText() }
                    backend.load(LocalModelManager.getModelFile(context).absolutePath, MAX_CPU_THREADS, grammar)
                }
                val slmText = backend.generate(SYSTEM_PROMPT, slmInput, 180)?.trim()
                if (!slmText.isNullOrBlank() && slmText.contains("PLAN A", ignoreCase = true)) {
                    val totalMs = (System.nanoTime() - t0) / 1_000_000.0
                    return LocalDraftResponse(
                        recommendation = slmText.replace("**", "").trim(),
                        draftContext = draftCtx,
                        slmInputJson = slmInput,
                        latencyMs = totalMs,
                        engineMode = "math_plus_slm"
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "Fallback a motor matemático rápido tras error SLM: ${e.message}")
            }
        }

        // 3. Modo instantáneo matemático (< 1 ms, ~0 MB RAM extra, seguro incluso en teléfonos de gama baja)
        val fastText = DraftMathEngine.renderFastTacticalText(mathRes)
        val totalMs = (System.nanoTime() - t0) / 1_000_000.0
        return LocalDraftResponse(
            recommendation = fastText,
            draftContext = draftCtx,
            slmInputJson = slmInput,
            latencyMs = totalMs,
            engineMode = "math_instant"
        )
    }
}
