package com.drafting.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Base64
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.hypot

class CaptureService : Service() {
    companion object {
        const val ACTION_SHOW_BUBBLE = "com.drafting.app.ACTION_SHOW_BUBBLE"
        const val ACTION_STOP_SERVICE = "com.drafting.app.ACTION_STOP_SERVICE"
    }

    private val NOTIFICATION_ID = 101
    private val CHANNEL_ID = "DraftingCaptureChannel"

    private lateinit var windowManager: WindowManager
    private lateinit var floatingView: View
    private var dismissOverlayView: FrameLayout? = null
    private var dismissCircleView: TextView? = null
    private var overlayParams: WindowManager.LayoutParams? = null

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    private var baseUrl: String? = null
    private var sessionToken: String? = null
    private var mainRole: String = "Auto"
    private var secondaryRole: String = "Auto"
    private var autofillRole: String = "Auto"
    private var gameMode: String = "wild_rift"
    private var isPremium: Boolean = false
    private var planTier: String = "plus"
    private var otpChampions: String = ""
    private var activeCreatorId: String? = null
    private var language: String = "es"

    // Memoria de contexto de la captura actual (se borra al arrastrar la burbuja al círculo X)
    private var lastCapturedBase64: String? = null
    private var lastDraftContext: String? = null
    private val seenChampionsInDraft = mutableListOf<String>()
    private var hasCapturedInCurrentMatch: Boolean = false

    // Variables de Narrador Táctico (TTS)
    private var tts: TextToSpeech? = null
    private var isTtsInitialized = false
    private var isTtsSpeaking = false
    private var lastRecommendationText: String? = null
    private var ttsSpeechRate: Float = 1.38f

    private val urlRegex = Regex("""(?i)(https?://|www\.|[a-z0-9-]+\.(com|net|org|gg|io|me|tv|co|xyz|app|link|ly|be)(/|\b))""")
    private val offensiveWords = setOf(
        "puto", "puta", "putos", "putas", "mierda", "pendejo", "pendeja", "cabron", "cabrón",
        "marica", "maricon", "maricón", "verga", "chinga", "chingar", "culero", "idiota",
        "imbecil", "imbécil", "estupido", "estúpido", "zorra", "malparido", "gonorrea",
        "hijueputa", "hdp", "ctm", "ptm", "spcrf", "alv", "mmg", "mamaguevo", "coño",
        "gilipollas", "subnormal", "retrasado", "pelotudo", "boludo", "conchudo", "pajero",
        "porra", "caralho", "merda", "buceta", "viado", "fdp", "arrombado", "babaca", "vtmnc",
        "fuck", "fucking", "shit", "bitch", "asshole", "bastard", "dick", "pussy", "cunt",
        "retard", "faggot", "nigger", "nigga", "whore", "slut", "stfu", "gtfo", "kys",
        "putain", "connard", "salope", "encule", "enculé", "batard", "bâtard", "ntm"
    )
    private val allowedShortGamingTerms = setOf(
        "xd", "gg", "wp", "ff", "afk", "fps", "ms", "jg", "cc", "cd", "cdr",
        "hp", "mr", "vs", "wr", "pc", "tp", "qss", "dps", "lvl"
    )

    private val prefsListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { sharedPrefs, key ->
        if (key == "language") {
            val updated = sharedPrefs.getString("language", "es") ?: "es"
            language = updated.lowercase().take(2)
            Handler(Looper.getMainLooper()).post {
                refreshOverlayTexts()
                updateForegroundNotification()
            }
        }
    }

    private fun getCurrentLang(): String {
        val saved = try {
            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).getString("language", null)
        } catch (_: Exception) {
            null
        }
        if (!saved.isNullOrBlank()) {
            language = saved.lowercase().take(2)
        }
        return language.lowercase().take(2)
    }

    private fun refreshOverlayTexts() {
        if (!::floatingView.isInitialized) return
        floatingView.findViewById<TextView>(R.id.messageTitle)?.text = overlayTr("title")
        floatingView.findViewById<TextView>(R.id.loadingTextView)?.text = overlayTr("analyzing_match")
        floatingView.findViewById<EditText>(R.id.chatInputEditText)?.hint = overlayTr("chat_hint")
    }

    private fun overlayTr(key: String): String {
        val lang = getCurrentLang()
        return when (lang) {
            "pt" -> when (key) {
                "title" -> "RECOMENDAÇÃO IA"
                "analyzing_match" -> "Analisando partida..."
                "reconsulting" -> "Pensando em alternativas..."
                "chatting" -> "Consultando treinador IA..."
                "analyzing_toast" -> "Analisando..."
                "copied" -> "Recomendação copiada para a área de transferência!"
                "view_translucent" -> "Visão: Translúcida (65%)"
                "view_solid" -> "Visão: Sólida (94%)"
                "size_compact" -> "Tamanho: Compacto"
                "size_standard" -> "Tamanho: Padrão"
                "size_wide" -> "Tamanho: Amplo"
                "chat_hint" -> "Pergunte sobre runas, itens ou dúvidas..."
                "guard_offensive" -> "Não podemos permitir palavras ofensivas, por favor seja educado."
                "guard_links" -> "Não é permitido enviar links no chat."
                "guard_words" -> "Máximo de 50 palavras permitido por mensagem."
                "memory_cleared" -> "Bolha ocultada e dados da partida limpos. Toque na notificação para chamá-la novamente."
                "notif_title" -> "Drafting ativo (Toque para chamar a bolha)"
                "notif_text" -> "Arraste a bolha até o (X) para ocultá-la ou toque em Desligar"
                "notif_show_bubble" -> "Chamar Bolha"
                "notif_power_off" -> "Desligar"
                "err_429" -> "Limite temporário atingido. Aguarde alguns instantes."
                "err_401" -> "Sua sessão expirou. Abra o app Drafting e faça login novamente."
                "err_402" -> "Sem consultas disponíveis. Abra o Drafting e toque em 'Obter consultas'."
                "err_net" -> "Sem conexão com o servidor. Verifique seu WiFi/dados ou Modo Jogo."
                "err_timeout" -> "O servidor demorou para responder. Tente novamente."
                else -> key
            }
            "en" -> when (key) {
                "title" -> "AI RECOMMENDATION"
                "analyzing_match" -> "Analyzing match..."
                "reconsulting" -> "Thinking of alternatives..."
                "chatting" -> "Asking AI coach..."
                "analyzing_toast" -> "Analyzing..."
                "copied" -> "Recommendation copied to clipboard!"
                "view_translucent" -> "View: Translucent (65%)"
                "view_solid" -> "View: Solid (94%)"
                "size_compact" -> "Size: Compact"
                "size_standard" -> "Size: Standard"
                "size_wide" -> "Size: Wide"
                "chat_hint" -> "Ask about runes, items, or strategy..."
                "guard_offensive" -> "We cannot allow offensive words, please be polite."
                "guard_links" -> "Links are not allowed in chat."
                "guard_words" -> "Maximum 50 words allowed per message."
                "memory_cleared" -> "Bubble hidden and match data cleared. Tap the notification to call it back."
                "notif_title" -> "Drafting active (Tap to summon bubble)"
                "notif_text" -> "Drag bubble to (X) to hide or tap Turn Off to stop"
                "notif_show_bubble" -> "Summon Bubble"
                "notif_power_off" -> "Turn Off"
                "err_429" -> "Temporary rate limit reached. Please wait a moment."
                "err_401" -> "Your session has expired. Open Drafting and sign in again."
                "err_402" -> "No queries available. Open Drafting and tap 'Get queries'."
                "err_net" -> "No connection to server. Check your WiFi/data or Game Mode restrictions."
                "err_timeout" -> "Server took too long to respond. Please try again."
                else -> key
            }
            "fr" -> when (key) {
                "title" -> "RECOMMANDATION IA"
                "analyzing_match" -> "Analyse de la partie..."
                "reconsulting" -> "Recherche d'alternatives..."
                "chatting" -> "Consultation du coach IA..."
                "analyzing_toast" -> "Analyse en cours..."
                "copied" -> "Recommandation copiée dans le presse-papiers !"
                "view_translucent" -> "Vue : Translucide (65%)"
                "view_solid" -> "Vue : Solide (94%)"
                "size_compact" -> "Taille : Compacte"
                "size_standard" -> "Taille : Standard"
                "size_wide" -> "Taille : Large"
                "chat_hint" -> "Demandez des runes, objets ou conseils..."
                "guard_offensive" -> "Nous ne pouvons pas autoriser les mots offensants, veuillez être poli."
                "guard_links" -> "Les liens ne sont pas autorisés dans le chat."
                "guard_words" -> "Maximum 50 mots autorisés par message."
                "memory_cleared" -> "Bulle masquée et données effacées. Appuyez sur la notification pour la rappeler."
                "notif_title" -> "Drafting actif (Appuyez pour afficher la bulle)"
                "notif_text" -> "Glissez la bulle vers (X) pour masquer ou appuyez sur Arrêter"
                "notif_show_bubble" -> "Afficher la bulle"
                "notif_power_off" -> "Arrêter"
                "err_429" -> "Limite temporaire atteinte. Veuillez patienter un instant."
                "err_401" -> "Votre session a expiré. Ouvrez Drafting et reconnectez-vous."
                "err_402" -> "Aucune requête disponible. Ouvrez Drafting et appuyez sur 'Obtenir des requêtes'."
                "err_net" -> "Aucune connexion au serveur. Vérifiez votre WiFi/données ou le Mode Jeu."
                "err_timeout" -> "Le serveur a mis trop de temps à répondre. Veuillez réessayer."
                else -> key
            }
            else -> when (key) {
                "title" -> "RECOMENDACIÓN AI"
                "analyzing_match" -> "Analizando partida..."
                "reconsulting" -> "Pensando en nuevas alternativas..."
                "chatting" -> "Consultando al entrenador IA..."
                "analyzing_toast" -> "Analizando..."
                "copied" -> "¡Recomendación copiada al portapapeles!"
                "view_translucent" -> "Vista: Traslúcida (65%)"
                "view_solid" -> "Vista: Sólida (94%)"
                "size_compact" -> "Tamaño: Compacto"
                "size_standard" -> "Tamaño: Estándar"
                "size_wide" -> "Tamaño: Amplio"
                "chat_hint" -> "Pregunta por runas, objetos o dudas..."
                "guard_offensive" -> "No podemos permitir palabras ofensivas, por favor sé educado."
                "guard_links" -> "No está permitido enviar links en el chat."
                "guard_words" -> "Máximo 50 palabras permitidas por mensaje."
                "memory_cleared" -> "Burbuja retirada y datos de la partida borrados. Toca la notificación para volver a llamarla."
                "notif_title" -> "Drafting activo (Toca para llamar a la burbuja)"
                "notif_text" -> "Lleva la burbuja al círculo (X) para retirarla o toca Apagar"
                "notif_show_bubble" -> "Llamar Burbuja"
                "notif_power_off" -> "Apagar"
                "err_429" -> "Has alcanzado el límite temporal. Espera unos minutos."
                "err_401" -> "Tu sesión ha expirado. Abre la app Drafting e inicia sesión nuevamente."
                "err_402" -> "Sin consultas disponibles. Abre Drafting y toca 'Obtener consultas'."
                "err_net" -> "Sin conexión con el servidor. Revisa tu WiFi/datos o la restricción de red en segundo plano del Modo Juego."
                "err_timeout" -> "El servidor tardó en responder. Por favor intenta de nuevo."
                else -> key
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        try {
            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE)
                .registerOnSharedPreferenceChangeListener(prefsListener)
        } catch (_: Exception) {}
        createNotificationChannel()
        initTts()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            notifyCaptureError("Capture service started without intent.")
            stopSelf()
            return START_NOT_STICKY
        }

        // Acciones desde la tarjeta de notificación estilo Shazam (Punto 1.3)
        when (intent.action) {
            ACTION_STOP_SERVICE -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SHOW_BUBBLE -> {
                Handler(Looper.getMainLooper()).post {
                    summonBubbleFromNotification()
                }
                return START_NOT_STICKY
            }
        }

        val code = intent.getIntExtra("code", 0)
        val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra("data", Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Intent>("data")
        }
        val incomingBaseUrl = intent.getStringExtra("baseUrl")
        if (!incomingBaseUrl.isNullOrBlank()) {
            baseUrl = incomingBaseUrl
            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).edit().putString("base_url", incomingBaseUrl).apply()
        }
        val incomingSessionToken = intent.getStringExtra("sessionToken")
        if (!incomingSessionToken.isNullOrBlank()) {
            sessionToken = incomingSessionToken
            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).edit().putString("session_token", incomingSessionToken).apply()
        }
        mainRole = "Auto"
        secondaryRole = "Auto"
        autofillRole = "Auto"
        isPremium = intent.getBooleanExtra("isPremium", false)
        planTier = intent.getStringExtra("planTier") ?: "plus"
        otpChampions = intent.getStringExtra("otpChampions") ?: ""
        activeCreatorId = intent.getStringExtra("activeCreatorId")
        val incomingGameMode = intent.getStringExtra("gameMode")
        if (!incomingGameMode.isNullOrBlank()) {
            gameMode = incomingGameMode.lowercase()
            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).edit().putString("game_mode", gameMode).apply()
        } else {
            gameMode = getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).getString("game_mode", "wild_rift") ?: "wild_rift"
        }
        val incomingLang = intent.getStringExtra("language")
        if (!incomingLang.isNullOrBlank()) {
            language = incomingLang.lowercase().take(2)
            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).edit().putString("language", language).apply()
        } else {
            language = getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).getString("language", "es") ?: "es"
        }

        updateForegroundNotification()

        if (code != android.app.Activity.RESULT_OK || data == null) {
            notifyCaptureError("Invalid capture permission data.")
            stopSelf()
            return START_NOT_STICKY
        }

        if (!Settings.canDrawOverlays(this)) {
            notifyCaptureError("Overlay permission is required to show the capture bubble.")
            stopSelf()
            return START_NOT_STICKY
        }

        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        Handler(Looper.getMainLooper()).postDelayed({
            try {
                mediaProjection = mpm.getMediaProjection(code, data)
                if (mediaProjection == null) {
                    notifyCaptureError("MediaProjection is null.")
                    stopSelf()
                    return@postDelayed
                }

                mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                    override fun onStop() {
                        super.onStop()
                        stopSelf()
                    }
                }, null)

                setupVirtualDisplay()
                showFloatingBubble()
            } catch (e: Throwable) {
                notifyCaptureError("Failed to start capture: ${e.message}")
                stopSelf()
            }
        }, 200)

        return START_NOT_STICKY
    }

    private fun summonBubbleFromNotification() {
        if (!::floatingView.isInitialized) {
            showFloatingBubble()
            return
        }
        floatingView.visibility = View.VISIBLE
        val expandedContainer = floatingView.findViewById<LinearLayout>(R.id.expandedContainer)
        val btnCollapsedBubble = floatingView.findViewById<ImageButton>(R.id.btnCollapsedBubble)
        btnCollapsedBubble?.visibility = View.GONE
        expandedContainer?.visibility = View.VISIBLE
        resetDraftMemoryAndUI(showToastMsg = false)
    }

    /**
     * Punto 1.2 Nota: Al llevar la burbuja al círculo con la (X), el sistema retira la burbuja
     * y borra todos los datos que dejó la imagen de la primera consulta para que no alucine
     * y esté 100% fresco para otra partida.
     */
    private fun resetDraftMemoryAndUI(showToastMsg: Boolean = true) {
        stopTts()
        enableOverlayKeyboardFocus(false)
        lastCapturedBase64 = null
        lastDraftContext = null
        lastRecommendationText = null
        seenChampionsInDraft.clear()
        hasCapturedInCurrentMatch = false

        if (::floatingView.isInitialized) {
            floatingView.findViewById<ImageButton>(R.id.btnCaptureGeneral)?.visibility = View.VISIBLE
            floatingView.findViewById<ImageButton>(R.id.btnRefreshDraft)?.visibility = View.GONE
            floatingView.findViewById<ImageButton>(R.id.btnTtsPlayPause)?.visibility = View.GONE
            floatingView.findViewById<ImageButton>(R.id.btnQuickChatBubble)?.visibility = View.GONE
            floatingView.findViewById<FrameLayout>(R.id.messageContainer)?.visibility = View.GONE
            floatingView.findViewById<EditText>(R.id.chatInputEditText)?.setText("")
            floatingView.findViewById<TextView>(R.id.resultTextView)?.text = ""
        }

        if (showToastMsg) {
            showToast(overlayTr("memory_cleared"))
        }
    }

    private fun setupVirtualDisplay() {
        try {
            val metrics = resources.displayMetrics
            val density = metrics.densityDpi
            val width = metrics.widthPixels
            val height = metrics.heightPixels

            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "DraftingCapture",
                width, height, density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader?.surface, null, null
            )

            if (virtualDisplay == null) {
                notifyCaptureError("Unable to create virtual display.")
                stopSelf()
            }
        } catch (e: Throwable) {
            notifyCaptureError("Virtual display error: ${e.message}")
            stopSelf()
        }
    }

    /**
     * Crea el círculo inferior con la (X) estilo Messenger / Shazam (Punto 1.1)
     */
    private fun setupDismissTargetOverlay(layoutFlag: Int) {
        if (dismissOverlayView != null) {
            try {
                windowManager.removeView(dismissOverlayView)
            } catch (_: Exception) {}
            dismissOverlayView = null
        }

        val container = FrameLayout(this).apply {
            visibility = View.GONE
        }

        val circleSize = dpToPx(64)
        val circleBg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor("#D91E293B"))
            setStroke(dpToPx(2), Color.parseColor("#EF4444"))
        }

        val xCircle = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#EF4444"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            gravity = Gravity.CENTER
            background = circleBg
            elevation = dpToPx(10).toFloat()
        }

        val lp = FrameLayout.LayoutParams(circleSize, circleSize).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            bottomMargin = dpToPx(38)
        }
        container.addView(xCircle, lp)

        val dismissParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            dpToPx(140),
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        }

        try {
            windowManager.addView(container, dismissParams)
            dismissOverlayView = container
            dismissCircleView = xCircle
        } catch (_: Exception) {}
    }

    private fun updateDismissCircleHighlight(isHovering: Boolean) {
        val circle = dismissCircleView ?: return
        val bg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            if (isHovering) {
                setColor(Color.parseColor("#EF4444"))
                setStroke(dpToPx(3), Color.parseColor("#FFFFFF"))
            } else {
                setColor(Color.parseColor("#D91E293B"))
                setStroke(dpToPx(2), Color.parseColor("#EF4444"))
            }
        }
        circle.background = bg
        circle.setTextColor(if (isHovering) Color.WHITE else Color.parseColor("#EF4444"))
        circle.scaleX = if (isHovering) 1.18f else 1.0f
        circle.scaleY = if (isHovering) 1.18f else 1.0f
    }

    private fun isInsideDismissCircle(rawX: Float, rawY: Float): Boolean {
        val metrics = resources.displayMetrics
        val centerX = metrics.widthPixels / 2f
        val centerY = metrics.heightPixels - dpToPx(70).toFloat()
        val distance = hypot((rawX - centerX).toDouble(), (rawY - centerY).toDouble())
        return distance <= dpToPx(68)
    }

    private fun enableOverlayKeyboardFocus(focusable: Boolean) {
        val params = overlayParams ?: return
        if (!::floatingView.isInitialized || !floatingView.isAttachedToWindow) return

        val newFlags = if (focusable) {
            params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
        } else {
            params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        }

        if (params.flags != newFlags) {
            params.flags = newFlags
            try {
                windowManager.updateViewLayout(floatingView, params)
            } catch (_: Exception) {}
        }

        if (!focusable) {
            val chatInput = floatingView.findViewById<EditText>(R.id.chatInputEditText)
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            if (chatInput != null) {
                imm?.hideSoftInputFromWindow(chatInput.windowToken, 0)
                chatInput.clearFocus()
            }
        }
    }

    private fun showFloatingBubble() {
        if (!Settings.canDrawOverlays(this)) {
            notifyCaptureError("Overlay permission is missing.")
            stopSelf()
            return
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        if (::floatingView.isInitialized) {
            try {
                windowManager.removeView(floatingView)
            } catch (_: Exception) {}
        }

        val layoutFlag: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        setupDismissTargetOverlay(layoutFlag)

        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        floatingView = inflater.inflate(R.layout.layout_overlay, null)

        val expandedContainer = floatingView.findViewById<LinearLayout>(R.id.expandedContainer)
        val btnCollapsedBubble = floatingView.findViewById<ImageButton>(R.id.btnCollapsedBubble)
        val btnCaptureGeneral = floatingView.findViewById<ImageButton>(R.id.btnCaptureGeneral)
        val btnRefreshDraft = floatingView.findViewById<ImageButton>(R.id.btnRefreshDraft)
        val btnTtsPlayPause = floatingView.findViewById<ImageButton>(R.id.btnTtsPlayPause)
        val btnHeaderTts = floatingView.findViewById<ImageButton>(R.id.btnHeaderTts)
        val btnQuickChatBubble = floatingView.findViewById<ImageButton>(R.id.btnQuickChatBubble)
        val btnCloseMessage = floatingView.findViewById<ImageButton>(R.id.btnCloseMessage)
        val btnCopyMessage = floatingView.findViewById<ImageButton>(R.id.btnCopyMessage)
        val btnCollapseChatBar = floatingView.findViewById<ImageButton>(R.id.btnCollapseChatBar)
        val chatInputEditText = floatingView.findViewById<EditText>(R.id.chatInputEditText)
        val btnSendChat = floatingView.findViewById<ImageButton>(R.id.btnSendChat)

        btnTtsPlayPause?.setOnClickListener {
            toggleTts()
        }

        btnHeaderTts?.setOnClickListener {
            toggleTts()
        }

        // 1ra Consulta: Toma captura, guarda contexto y reemplaza el botón de captura por el de Reconsultar
        btnCaptureGeneral?.setOnClickListener {
            stopTts()
            enableOverlayKeyboardFocus(false)
            seenChampionsInDraft.clear()
            captureScreenAndSend("draft", 0)
        }

        // Botón de Reconsultar (Punto 1.2 y 1.6): NO toma otra captura, usa los datos que dejó la primera imagen
        btnRefreshDraft?.setOnClickListener {
            stopTts()
            enableOverlayKeyboardFocus(false)
            if (!lastDraftContext.isNullOrBlank()) {
                Handler(Looper.getMainLooper()).post {
                    refreshOverlayTexts()
                    floatingView.findViewById<TextView>(R.id.loadingTextView)?.text = overlayTr("reconsulting")
                    adjustMessageContainerPosition()
                    floatingView.findViewById<FrameLayout>(R.id.messageContainer)?.visibility = View.VISIBLE
                    floatingView.findViewById<LinearLayout>(R.id.loadingLayout)?.visibility = View.VISIBLE
                    floatingView.findViewById<ScrollView>(R.id.resultScrollView)?.visibility = View.GONE
                }
                sendReconsultToBackend(lastDraftContext!!, seenChampionsInDraft.joinToString(", "))
            } else if (lastCapturedBase64 != null) {
                Handler(Looper.getMainLooper()).post {
                    refreshOverlayTexts()
                    floatingView.findViewById<TextView>(R.id.loadingTextView)?.text = overlayTr("reconsulting")
                    adjustMessageContainerPosition()
                    floatingView.findViewById<FrameLayout>(R.id.messageContainer)?.visibility = View.VISIBLE
                    floatingView.findViewById<LinearLayout>(R.id.loadingLayout)?.visibility = View.VISIBLE
                    floatingView.findViewById<ScrollView>(R.id.resultScrollView)?.visibility = View.GONE
                }
                sendToBackend(lastCapturedBase64!!, "draft", seenChampionsInDraft.joinToString(", "))
            } else {
                seenChampionsInDraft.clear()
                captureScreenAndSend("draft", 0)
            }
        }

        btnCollapsedBubble?.setOnClickListener {
            btnCollapsedBubble.visibility = View.GONE
            expandedContainer?.visibility = View.VISIBLE
        }

        // Convertir el panel/chat en un botón pequeño para que no estorbe en la pantalla (Punto 1.8)
        btnCloseMessage?.setOnClickListener {
            enableOverlayKeyboardFocus(false)
            floatingView.findViewById<FrameLayout>(R.id.messageContainer)?.visibility = View.GONE
            btnQuickChatBubble?.visibility = View.VISIBLE
        }

        btnQuickChatBubble?.setOnClickListener {
            val msgContainer = floatingView.findViewById<FrameLayout>(R.id.messageContainer)
            if (msgContainer?.visibility == View.VISIBLE) {
                enableOverlayKeyboardFocus(false)
                msgContainer.visibility = View.GONE
            } else {
                adjustMessageContainerPosition()
                msgContainer?.visibility = View.VISIBLE
            }
        }

        btnCollapseChatBar?.setOnClickListener {
            val input = floatingView.findViewById<EditText>(R.id.chatInputEditText)
            val sendBtn = floatingView.findViewById<ImageButton>(R.id.btnSendChat)
            if (input?.visibility == View.VISIBLE) {
                enableOverlayKeyboardFocus(false)
                input.visibility = View.GONE
                sendBtn?.visibility = View.GONE
            } else {
                input?.visibility = View.VISIBLE
                sendBtn?.visibility = View.VISIBLE
            }
        }

        // Chatbot en Tiempo Real (Punto 1.8)
        chatInputEditText?.setOnTouchListener { v, event ->
            if (event.action == MotionEvent.ACTION_DOWN) {
                enableOverlayKeyboardFocus(true)
                v.requestFocus()
                Handler(Looper.getMainLooper()).postDelayed({
                    val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                    imm?.showSoftInput(v, InputMethodManager.SHOW_IMPLICIT)
                }, 80)
            }
            false
        }

        chatInputEditText?.setOnEditorActionListener { _, actionId, event ->
            if (actionId == EditorInfo.IME_ACTION_SEND ||
                (event != null && event.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN)
            ) {
                submitChatQuestion()
                true
            } else {
                false
            }
        }

        btnSendChat?.setOnClickListener {
            submitChatQuestion()
        }

        btnCopyMessage?.setOnClickListener {
            val resultTextView = floatingView.findViewById<TextView>(R.id.resultTextView)
            val textToCopy = resultTextView?.text?.toString()?.trim() ?: ""
            if (textToCopy.isNotEmpty()) {
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = ClipData.newPlainText("Drafting", textToCopy)
                clipboard.setPrimaryClip(clip)
                Toast.makeText(applicationContext, overlayTr("copied"), Toast.LENGTH_SHORT).show()
            }
        }

        val messageContainer = floatingView.findViewById<FrameLayout>(R.id.messageContainer)
        val btnToggleOpacity = floatingView.findViewById<ImageButton>(R.id.btnToggleOpacity)
        val btnToggleSize = floatingView.findViewById<ImageButton>(R.id.btnToggleSize)
        val btnResizeCorner = floatingView.findViewById<ImageView>(R.id.btnResizeCorner)
        val prefs = getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE)

        // 1. Restaurar Opacidad guardada
        var isLowOpacity = prefs.getBoolean("overlay_low_opacity", false)
        messageContainer?.alpha = if (isLowOpacity) 0.65f else 0.94f

        btnToggleOpacity?.setOnClickListener {
            isLowOpacity = !isLowOpacity
            messageContainer?.alpha = if (isLowOpacity) 0.65f else 0.94f
            prefs.edit().putBoolean("overlay_low_opacity", isLowOpacity).apply()
            showToast(if (isLowOpacity) overlayTr("view_translucent") else overlayTr("view_solid"))
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        overlayParams = params

        params.gravity = Gravity.TOP or Gravity.START
        params.x = prefs.getInt("overlay_pos_x", 0)
        params.y = prefs.getInt("overlay_pos_y", 100)

        // 2. Restaurar y controlar Tamaño
        fun applyContainerSize(widthPx: Int, heightPx: Int) {
            if (messageContainer == null) return
            val lp = messageContainer.layoutParams
            lp.width = widthPx
            lp.height = heightPx
            messageContainer.layoutParams = lp
            try {
                if (floatingView.isAttachedToWindow) {
                    windowManager.updateViewLayout(floatingView, params)
                }
            } catch (_: Exception) {}
        }

        var sizeIndex = prefs.getInt("overlay_size_index", 1)
        val savedCustomWidth = prefs.getInt("overlay_custom_width", 0)
        val savedCustomHeight = prefs.getInt("overlay_custom_height", 0)

        if (savedCustomWidth > 0 && savedCustomHeight > 0) {
            applyContainerSize(savedCustomWidth, savedCustomHeight)
        } else {
            val (wDp, hDp) = when (sizeIndex) {
                0 -> Pair(290, 210)
                2 -> Pair(420, 320)
                else -> Pair(340, 260)
            }
            applyContainerSize(dpToPx(wDp), dpToPx(hDp))
        }

        btnToggleSize?.setOnClickListener {
            sizeIndex = (sizeIndex + 1) % 3
            prefs.edit().putInt("overlay_size_index", sizeIndex)
                .remove("overlay_custom_width")
                .remove("overlay_custom_height").apply()
            val (wDp, hDp, label) = when (sizeIndex) {
                0 -> Triple(290, 210, overlayTr("size_compact"))
                2 -> Triple(420, 320, overlayTr("size_wide"))
                else -> Triple(340, 260, overlayTr("size_standard"))
            }
            applyContainerSize(dpToPx(wDp), dpToPx(hDp))
            showToast(label)
        }

        // 3. Redimensionar libremente arrastrando desde la esquina
        btnResizeCorner?.setOnTouchListener(object : View.OnTouchListener {
            private var initW: Int = 0
            private var initH: Int = 0
            private var touchX: Float = 0f
            private var touchY: Float = 0f

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                if (messageContainer == null) return false
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initW = messageContainer.width
                        initH = messageContainer.height
                        touchX = event.rawX
                        touchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - touchX).toInt()
                        val dy = (event.rawY - touchY).toInt()
                        val minW = dpToPx(260)
                        val minH = dpToPx(180)
                        val maxW = dpToPx(550)
                        val maxH = dpToPx(420)

                        val newW = (initW + dx).coerceIn(minW, maxW)
                        val newH = (initH + dy).coerceIn(minH, maxH)

                        applyContainerSize(newW, newH)
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        prefs.edit().putInt("overlay_custom_width", messageContainer.width)
                            .putInt("overlay_custom_height", messageContainer.height).apply()
                        return true
                    }
                }
                return false
            }
        })

        refreshOverlayTexts()

        // Hacer arrastrable el botón de captura, el de reconsultar, la burbuja y el encabezado hacia el círculo (X)
        if (btnCaptureGeneral != null) setupDragWithDismiss(btnCaptureGeneral, params)
        if (btnRefreshDraft != null) setupDragWithDismiss(btnRefreshDraft, params)
        if (btnCollapsedBubble != null) setupDragWithDismiss(btnCollapsedBubble, params)
        floatingView.findViewById<TextView>(R.id.messageTitle)?.let { setupDragWithDismiss(it, params) }

        adjustMessageContainerPosition()

        try {
            windowManager.addView(floatingView, params)
        } catch (e: Exception) {
            notifyCaptureError("Overlay view could not be displayed: ${e.message}")
            stopSelf()
        }
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }

    /**
     * Punto 1.1 y 1.2 Nota: Al arrastrar la burbuja muestra el círculo inferior con una (X).
     * Al soltarla dentro del círculo, retira la burbuja de la pantalla y borra todos los datos
     * de la primera consulta para que no alucine en la siguiente partida.
     */
    private fun setupDragWithDismiss(view: View, params: WindowManager.LayoutParams) {
        view.setOnTouchListener(object : View.OnTouchListener {
            private var initialX: Int = 0
            private var initialY: Int = 0
            private var initialTouchX: Float = 0f
            private var initialTouchY: Float = 0f
            private var isDragging = false
            private val CLICK_DRAG_TOLERANCE = dpToPx(8).toFloat()

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isDragging = false
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        if (!isDragging && (abs(dx) > CLICK_DRAG_TOLERANCE || abs(dy) > CLICK_DRAG_TOLERANCE)) {
                            isDragging = true
                            dismissOverlayView?.visibility = View.VISIBLE
                        }
                        if (isDragging) {
                            params.x = initialX + dx.toInt()
                            params.y = initialY + dy.toInt()
                            try {
                                windowManager.updateViewLayout(floatingView, params)
                            } catch (_: Exception) {}
                            updateDismissCircleHighlight(isInsideDismissCircle(event.rawX, event.rawY))
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        dismissOverlayView?.visibility = View.GONE
                        updateDismissCircleHighlight(false)

                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        if (!isDragging && abs(dx) < CLICK_DRAG_TOLERANCE && abs(dy) < CLICK_DRAG_TOLERANCE) {
                            v.performClick()
                        } else if (isInsideDismissCircle(event.rawX, event.rawY)) {
                            // Retirar burbuja de la pantalla y borrar datos de la partida
                            floatingView.visibility = View.GONE
                            resetDraftMemoryAndUI(showToastMsg = true)
                        } else {
                            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).edit()
                                .putInt("overlay_pos_x", params.x)
                                .putInt("overlay_pos_y", params.y).apply()
                            adjustMessageContainerPosition()
                        }
                        isDragging = false
                        return true
                    }
                }
                return false
            }
        })
    }

    /**
     * Validador local del Asistente Puente (Punto 1.8):
     * - Prohibido enviar links
     * - Máximo 50 palabras
     * - Prohibido palabras groseras o mensajes de solo iniciales como SPCRF
     */
    private fun validateChatInputLocally(rawText: String): String? {
        val text = rawText.trim()
        if (urlRegex.containsMatchIn(text)) {
            return overlayTr("guard_links")
        }
        val words = text.split(Regex("""\s+""")).filter { it.isNotEmpty() }
        if (words.size > 50) {
            return overlayTr("guard_words")
        }

        // Revisar palabras ofensivas o siglas sin vocales como SPCRF
        val normalized = text.lowercase()
            .replace("0", "o").replace("1", "i").replace("3", "e")
            .replace("4", "a").replace("@", "a").replace("$", "s")
        val cleanTokens = normalized.split(Regex("""[^a-záéíóúüñç]+""")).filter { it.isNotEmpty() }

        for (token in cleanTokens) {
            if (offensiveWords.contains(token)) {
                return overlayTr("guard_offensive")
            }
            if (token.length >= 2 && !allowedShortGamingTerms.contains(token)) {
                val hasVowel = token.any { it in "aeiouyáéíóúäëïöü" }
                if (!hasVowel) {
                    return overlayTr("guard_offensive")
                }
            }
        }
        return null
    }

    private fun submitChatQuestion() {
        if (!::floatingView.isInitialized) return
        val inputView = floatingView.findViewById<EditText>(R.id.chatInputEditText) ?: return
        val message = inputView.text?.toString()?.trim() ?: ""
        if (message.isEmpty()) return

        stopTts()
        enableOverlayKeyboardFocus(false)

        // Puente guardián local (ahorra llamada de red y tokens si hay insulto, SPCRF, link o > 50 palabras)
        val guardError = validateChatInputLocally(message)
        if (guardError != null) {
            inputView.setText("")
            showResultOnUI(guardError, autoSpeak = true)
            return
        }

        inputView.setText("")
        Handler(Looper.getMainLooper()).post {
            refreshOverlayTexts()
            floatingView.findViewById<TextView>(R.id.loadingTextView)?.text = overlayTr("chatting")
            adjustMessageContainerPosition()
            floatingView.findViewById<FrameLayout>(R.id.messageContainer)?.visibility = View.VISIBLE
            floatingView.findViewById<LinearLayout>(R.id.loadingLayout)?.visibility = View.VISIBLE
            floatingView.findViewById<ScrollView>(R.id.resultScrollView)?.visibility = View.GONE
        }

        sendChatToBackend(message, lastDraftContext ?: "")
    }

    private fun captureScreenAndSend(queryType: String, retryCount: Int = 0) {
        try {
            if (::floatingView.isInitialized && retryCount == 0) {
                floatingView.findViewById<FrameLayout>(R.id.messageContainer)?.visibility = View.GONE
            }

            val image = imageReader?.acquireLatestImage()

            if (image == null) {
                if (retryCount < 3) {
                    Handler(Looper.getMainLooper()).postDelayed({ captureScreenAndSend(queryType, retryCount + 1) }, 500)
                    return
                }
                notifyCaptureError("No image available from screen capture.")
                return
            }

            Handler(Looper.getMainLooper()).post {
                refreshOverlayTexts()
                adjustMessageContainerPosition()
                floatingView.findViewById<FrameLayout>(R.id.messageContainer)?.visibility = View.VISIBLE
                floatingView.findViewById<LinearLayout>(R.id.loadingLayout)?.visibility = View.VISIBLE
                floatingView.findViewById<ScrollView>(R.id.resultScrollView)?.visibility = View.GONE
            }

            val planes = image.planes
            if (planes.isEmpty()) {
                image.close()
                notifyCaptureError("Captured image has no planes.")
                return
            }

            val buffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val imgWidth = image.width
            val imgHeight = image.height
            val rowPadding = rowStride - pixelStride * imgWidth

            val bitmap = Bitmap.createBitmap(
                imgWidth + rowPadding / pixelStride,
                imgHeight,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)
            image.close()

            val croppedBitmap = Bitmap.createBitmap(bitmap, 0, 0, imgWidth, imgHeight)

            val maxDimension = 1280
            val largestSide = maxOf(imgWidth, imgHeight)
            val finalBitmap = if (largestSide > maxDimension) {
                val scale = maxDimension.toFloat() / largestSide.toFloat()
                val targetW = (imgWidth * scale).toInt().coerceAtLeast(1)
                val targetH = (imgHeight * scale).toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(croppedBitmap, targetW, targetH, true)
            } else {
                croppedBitmap
            }

            val stream = ByteArrayOutputStream()
            finalBitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)
            val byteArray = stream.toByteArray()
            val base64Image = Base64.encodeToString(byteArray, Base64.NO_WRAP)

            if (finalBitmap != croppedBitmap) finalBitmap.recycle()
            croppedBitmap.recycle()
            bitmap.recycle()

            sendToBackend(base64Image, queryType)
        } catch (e: Exception) {
            if (retryCount < 3) {
                Handler(Looper.getMainLooper()).postDelayed({ captureScreenAndSend(queryType, retryCount + 1) }, 500)
            } else {
                notifyCaptureError("Fallo al capturar: ${e.message}")
            }
        } catch (e: Error) {
            if (retryCount < 3) {
                Handler(Looper.getMainLooper()).postDelayed({ captureScreenAndSend(queryType, retryCount + 1) }, 500)
            } else {
                notifyCaptureError("Error crítico: ${e.message}")
            }
        }
    }

    private fun sendResultToActivity(status: String, code: Int, message: String) {
        val intent = Intent("com.drafting.app.RESULT_ACTION")
        intent.setPackage(packageName)
        intent.putExtra("status", status)
        intent.putExtra("code", code)
        intent.putExtra("message", message)
        sendBroadcast(intent)
    }

    private fun extractChampionsFromRec(text: String) {
        val patternA = Regex("""(?:PLAN|PLANO)\s*A\s*:\s*([^•\n\r]+)""", RegexOption.IGNORE_CASE)
        patternA.find(text)?.groupValues?.getOrNull(1)?.trim()?.let { name ->
            if (name.isNotEmpty() && !seenChampionsInDraft.contains(name)) {
                seenChampionsInDraft.add(name)
            }
        }

        val simSectionIndex = text.indexOfAny(
            listOf("Recomendaciones similares:", "Recomendações semelhantes:", "Similar recommendations:", "Recommandations similaires:"),
            ignoreCase = true
        )
        val textToSearch = if (simSectionIndex != -1) text.substring(simSectionIndex) else text

        val patternSim = Regex("""•\s*([^:\n\r]+):""", RegexOption.IGNORE_CASE)
        patternSim.findAll(textToSearch).forEach { match ->
            val name = match.groupValues.getOrNull(1)?.trim() ?: ""
            if (name.isNotEmpty() && !seenChampionsInDraft.contains(name)) {
                val lower = name.lowercase()
                if (!lower.contains("hechizo") && !lower.contains("runa") && !lower.contains("plan") &&
                    !lower.contains("spell") && !lower.contains("feitiço") && !lower.contains("sort") &&
                    !lower.contains("sinerg") && !lower.contains("build") && !lower.contains("combo") &&
                    !lower.contains("táctica") && !lower.contains("tactica") && !lower.contains("objeto")
                ) {
                    seenChampionsInDraft.add(name)
                }
            }
        }
    }

    private fun sendToBackend(base64Image: String, queryType: String, excludeChampions: String = "") {
        lastCapturedBase64 = base64Image
        showToast(overlayTr("analyzing_toast"))
        val payload = JSONObject().apply {
            put("image_base64", base64Image)
            put("main_role", "Auto")
            put("secondary_role", "Auto")
            put("autofill_role", "Auto")
            put("query_type", queryType)
            put("otp_champions", otpChampions)
            put("game_mode", gameMode)
            put("language", getCurrentLang())
            if (excludeChampions.isNotBlank()) {
                put("exclude_champions", excludeChampions)
            }
            if (!activeCreatorId.isNullOrEmpty()) {
                put("active_creator_id", activeCreatorId)
            }
        }
        postJsonToEndpoint("/api/v1/draft/analyze", payload, isInitialOrReconsult = true)
    }

    private fun sendReconsultToBackend(draftContext: String, excludeChampions: String) {
        showToast(overlayTr("reconsulting"))
        val payload = JSONObject().apply {
            put("draft_context", draftContext)
            put("otp_champions", otpChampions)
            put("game_mode", gameMode)
            put("language", getCurrentLang())
            if (excludeChampions.isNotBlank()) {
                put("exclude_champions", excludeChampions)
            }
        }
        postJsonToEndpoint("/api/v1/draft/reconsult", payload, isInitialOrReconsult = true)
    }

    private fun sendChatToBackend(message: String, draftContext: String) {
        val payload = JSONObject().apply {
            put("message", message)
            put("draft_context", draftContext)
            put("otp_champions", otpChampions)
            put("game_mode", gameMode)
            put("language", getCurrentLang())
        }
        postJsonToEndpoint("/api/v1/draft/chat", payload, isInitialOrReconsult = false)
    }

    private fun postJsonToEndpoint(endpointPath: String, jsonParam: JSONObject, isInitialOrReconsult: Boolean) {
        thread {
            val prefs = getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE)
            val currentLang = getCurrentLang()
            val base = (baseUrl?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() }
                ?: prefs.getString("base_url", null)?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() }
                ?: BuildConfig.BASE_URL.trimEnd('/'))
            if (base.isEmpty()) {
                showResultOnUI("Error: BASE_URL not configured.", autoSpeak = false)
                sendResultToActivity("error", 500, "BASE_URL is not configured")
                return@thread
            }

            val currentToken = sessionToken?.takeIf { it.isNotEmpty() }
                ?: prefs.getString("session_token", null)?.takeIf { it.isNotEmpty() }

            val maxAttempts = 3
            var lastException: Exception? = null

            for (attempt in 1..maxAttempts) {
                var conn: HttpURLConnection? = null
                try {
                    val url = URL("$base$endpointPath")
                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                    val activeNet = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) cm?.activeNetwork else null
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && activeNet != null) {
                        try {
                            cm?.bindProcessToNetwork(activeNet)
                        } catch (_: Exception) {}
                    }
                    val rawConn = if (activeNet != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        activeNet.openConnection(url)
                    } else {
                        url.openConnection()
                    }
                    conn = (rawConn as HttpURLConnection).apply {
                        requestMethod = "POST"
                        setRequestProperty("Content-Type", "application/json")
                        setRequestProperty("Accept", "application/json")
                        setRequestProperty("Accept-Language", currentLang)
                        setRequestProperty("Connection", "close")
                        if (!currentToken.isNullOrEmpty()) {
                            setRequestProperty("Authorization", "Bearer $currentToken")
                        }
                        connectTimeout = 15000
                        readTimeout = 40000
                        doOutput = true
                        doInput = true
                    }

                    conn.outputStream.use { out ->
                        OutputStreamWriter(out, Charsets.UTF_8).use { writer ->
                            writer.write(jsonParam.toString())
                            writer.flush()
                        }
                    }

                    val responseCode = conn.responseCode
                    if (responseCode == HttpURLConnection.HTTP_OK) {
                        val response = conn.inputStream.bufferedReader().use { it.readText() }
                        val jsonResponse = JSONObject(response)
                        val rec = jsonResponse.optString("recommendation", "")
                        val returnedCtx = jsonResponse.optString("draft_context", "")
                        val blockedByGuard = jsonResponse.optBoolean("blocked_by_guard", false)

                        if (returnedCtx.isNotBlank()) {
                            lastDraftContext = returnedCtx
                        }
                        if (isInitialOrReconsult) {
                            extractChampionsFromRec(rec)
                            hasCapturedInCurrentMatch = true
                        }
                        showResultOnUI(rec, autoSpeak = true)
                        if (!blockedByGuard) {
                            sendResultToActivity("success", 200, rec)
                        }
                        return@thread
                    } else if (responseCode == 429) {
                        showResultOnUI(overlayTr("err_429"), autoSpeak = false)
                        sendResultToActivity("error", 429, overlayTr("err_429"))
                        return@thread
                    } else if (responseCode == 401) {
                        showResultOnUI(overlayTr("err_401"), autoSpeak = false)
                        sendResultToActivity("error", 401, overlayTr("err_401"))
                        return@thread
                    } else if (responseCode == 402) {
                        showResultOnUI(overlayTr("err_402"), autoSpeak = false)
                        sendResultToActivity("error", 402, overlayTr("err_402"))
                        return@thread
                    } else {
                        val errorResponse = try {
                            conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                        } catch (_: Exception) { "" }

                        val displayMsg = if (errorResponse.isNotEmpty()) "Error: $errorResponse" else "Error: $responseCode"
                        showResultOnUI(displayMsg, autoSpeak = false)
                        sendResultToActivity("error", responseCode, displayMsg)
                        return@thread
                    }
                } catch (e: Exception) {
                    lastException = e
                    conn?.disconnect()
                    if (attempt < maxAttempts) {
                        try {
                            Thread.sleep(800)
                        } catch (_: InterruptedException) {}
                    }
                } finally {
                    conn?.disconnect()
                }
            }

            lastException?.let { e ->
                e.printStackTrace()
                val friendlyMsg = when (e) {
                    is java.net.UnknownHostException -> overlayTr("err_net")
                    is java.net.SocketTimeoutException -> overlayTr("err_timeout")
                    else -> "Error: " + (e.message ?: e.javaClass.simpleName)
                }
                showResultOnUI(friendlyMsg, autoSpeak = false)
                sendResultToActivity("error", 500, friendlyMsg)
            }
        }
    }

    /**
     * Puntos 1.2 y 1.5:
     * - Al recibir respuesta de captura, el botón principal de Captura es reemplazado por el botón de Reconsultar.
     * - El botón de Voz aparece y reproduce el audio automáticamente una vez que aparece la respuesta.
     */
    private fun showResultOnUI(text: String, autoSpeak: Boolean = true) {
        Handler(Looper.getMainLooper()).post {
            if (!::floatingView.isInitialized) return@post
            val cleanText = text.replace("**", "").replace("###", "").replace("##", "").trim()
            lastRecommendationText = cleanText
            updateTtsButtonState(false)
            refreshOverlayTexts()
            adjustMessageContainerPosition()

            if (hasCapturedInCurrentMatch) {
                floatingView.findViewById<ImageButton>(R.id.btnCaptureGeneral)?.visibility = View.GONE
                floatingView.findViewById<ImageButton>(R.id.btnRefreshDraft)?.visibility = View.VISIBLE
                floatingView.findViewById<ImageButton>(R.id.btnTtsPlayPause)?.visibility = View.VISIBLE
            }

            floatingView.findViewById<FrameLayout>(R.id.messageContainer)?.visibility = View.VISIBLE
            floatingView.findViewById<LinearLayout>(R.id.loadingLayout)?.visibility = View.GONE
            floatingView.findViewById<ScrollView>(R.id.resultScrollView)?.visibility = View.VISIBLE
            floatingView.findViewById<TextView>(R.id.resultTextView)?.text = cleanText

            if (autoSpeak && cleanText.isNotEmpty()) {
                playTts()
            }
        }
    }

    private fun adjustMessageContainerPosition() {
        if (!::floatingView.isInitialized) return
        val expandedContainer = floatingView.findViewById<LinearLayout>(R.id.expandedContainer) ?: return
        val messageContainer = floatingView.findViewById<FrameLayout>(R.id.messageContainer) ?: return
        val controlsContainer = floatingView.findViewById<LinearLayout>(R.id.controlsContainer) ?: return
        val metrics = resources.displayMetrics
        val screenWidth = metrics.widthPixels

        val params = floatingView.layoutParams as? WindowManager.LayoutParams ?: return
        val marginPx = (10 * metrics.density).toInt()

        expandedContainer.removeAllViews()
        if (params.x < screenWidth / 2) {
            expandedContainer.addView(controlsContainer)
            expandedContainer.addView(messageContainer)
            val layoutParams = messageContainer.layoutParams as LinearLayout.LayoutParams
            layoutParams.marginStart = marginPx
            layoutParams.marginEnd = 0
            messageContainer.layoutParams = layoutParams
        } else {
            expandedContainer.addView(messageContainer)
            expandedContainer.addView(controlsContainer)
            val layoutParams = messageContainer.layoutParams as LinearLayout.LayoutParams
            layoutParams.marginStart = 0
            layoutParams.marginEnd = marginPx
            messageContainer.layoutParams = layoutParams
        }
    }

    private fun notifyCaptureError(message: String) {
        showToast(message)
        sendResultToActivity("error", 500, message)
        showResultOnUI(message, autoSpeak = false)
    }

    private fun showToast(msg: String) {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Drafting Capture & Assistant",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun updateForegroundNotification() {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.notify(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) {}
    }

    /**
     * Punto 1.3: Tarjeta de notificación estilo Shazam:
     * - Al presionar en la notificación o en el botón "Llamar Burbuja", invoca la burbuja sin abrir todos los controles.
     * - Incluye el botón "Apagar" para finalizar el sistema definitivamente cuando el usuario quiera.
     */
    private fun buildNotification(): Notification {
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val showBubbleIntent = Intent(this, CaptureService::class.java).apply {
            action = ACTION_SHOW_BUBBLE
        }
        val showBubblePending = PendingIntent.getService(this, 301, showBubbleIntent, pendingFlags)

        val stopServiceIntent = Intent(this, CaptureService::class.java).apply {
            action = ACTION_STOP_SERVICE
        }
        val stopServicePending = PendingIntent.getService(this, 302, stopServiceIntent, pendingFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        @Suppress("DEPRECATION")
        return builder
            .setContentTitle(overlayTr("notif_title"))
            .setContentText(overlayTr("notif_text"))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(showBubblePending)
            .addAction(android.R.drawable.ic_menu_view, overlayTr("notif_show_bubble"), showBubblePending)
            .addAction(android.R.drawable.ic_lock_power_off, overlayTr("notif_power_off"), stopServicePending)
            .build()
    }

    // -------------------------------------------------------------
    // GESTIÓN DE NARRADOR TÁCTICO POR VOZ (TTS DEL TELÉFONO)
    // -------------------------------------------------------------
    private fun initTts() {
        if (tts != null) return
        try {
            tts = TextToSpeech(applicationContext) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    isTtsInitialized = true
                    applyTtsLanguage()
                    tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {
                            Handler(Looper.getMainLooper()).post {
                                isTtsSpeaking = true
                                updateTtsButtonState(true)
                            }
                        }

                        override fun onDone(utteranceId: String?) {
                            Handler(Looper.getMainLooper()).post {
                                isTtsSpeaking = false
                                updateTtsButtonState(false)
                            }
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) {
                            Handler(Looper.getMainLooper()).post {
                                isTtsSpeaking = false
                                updateTtsButtonState(false)
                            }
                        }
                    })
                    // Si ya había texto listo para reproducir al terminar de inicializar, reproducirlo
                    if (!lastRecommendationText.isNullOrBlank() && hasCapturedInCurrentMatch) {
                        Handler(Looper.getMainLooper()).post {
                            playTts()
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun applyTtsLanguage() {
        if (!isTtsInitialized || tts == null) return
        val locale = when (getCurrentLang()) {
            "pt" -> Locale("pt", "BR")
            "en" -> Locale.US
            "fr" -> Locale.FRANCE
            else -> Locale("es", "ES")
        }
        try {
            tts?.language = locale
            tts?.setSpeechRate(ttsSpeechRate)
            tts?.setPitch(1.0f)
        } catch (_: Exception) {}
    }

    private fun cleanTextForSpeech(fullText: String): String {
        if (fullText.isBlank()) return ""
        var clean = fullText.replace("*", "")
        clean = clean.replace(Regex("""(?m)^#+\s*"""), "")
        clean = clean.replace(Regex("""(?m)^\s*[•\-\+]\s*"""), "")
        clean = clean.replace(":", ". ")
        clean = clean.replace(Regex("""\n+"""), ". ")
        clean = clean.replace(Regex("""\s+"""), " ").trim()
        return clean
    }

    private fun toggleTts() {
        if (isTtsSpeaking) {
            stopTts()
        } else {
            playTts()
        }
    }

    private fun stopTts() {
        try {
            tts?.stop()
        } catch (_: Exception) {}
        isTtsSpeaking = false
        updateTtsButtonState(false)
    }

    private fun playTts() {
        val text = lastRecommendationText
        if (text.isNullOrBlank()) return

        if (!isTtsInitialized || tts == null) {
            initTts()
            return
        }

        applyTtsLanguage()
        val speechText = cleanTextForSpeech(text)
        if (speechText.isBlank()) return

        val params = android.os.Bundle()
        params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "drafting_callout")

        val maxChunk = 3500
        if (speechText.length <= maxChunk) {
            val res = tts?.speak(speechText, TextToSpeech.QUEUE_FLUSH, params, "drafting_callout")
            if (res == TextToSpeech.SUCCESS) {
                isTtsSpeaking = true
                updateTtsButtonState(true)
            }
        } else {
            val sentences = speechText.split(". ")
            var first = true
            for (sentence in sentences) {
                val chunk = sentence.trim()
                if (chunk.isEmpty()) continue
                val mode = if (first) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
                tts?.speak("$chunk.", mode, params, "drafting_callout")
                first = false
            }
            isTtsSpeaking = true
            updateTtsButtonState(true)
        }
    }

    private fun updateTtsButtonState(speaking: Boolean) {
        Handler(Looper.getMainLooper()).post {
            if (!::floatingView.isInitialized) return@post
            val btnBig = floatingView.findViewById<ImageButton>(R.id.btnTtsPlayPause)
            val btnHeader = floatingView.findViewById<ImageButton>(R.id.btnHeaderTts)

            if (speaking) {
                btnBig?.setImageResource(R.drawable.ic_tts_pause)
                btnBig?.setBackgroundResource(R.drawable.bg_hextech_tts_active)
                btnBig?.setColorFilter(Color.parseColor("#10B981"))

                btnHeader?.setImageResource(R.drawable.ic_tts_pause)
                btnHeader?.setColorFilter(Color.parseColor("#10B981"))
            } else {
                btnBig?.setImageResource(R.drawable.ic_tts_play)
                btnBig?.setBackgroundResource(R.drawable.bg_hextech_tts)
                btnBig?.setColorFilter(Color.parseColor("#00E5FF"))

                btnHeader?.setImageResource(R.drawable.ic_tts_play)
                btnHeader?.setColorFilter(Color.parseColor("#00E5FF"))
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopTts()
        try {
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
        try {
            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE)
                .unregisterOnSharedPreferenceChangeListener(prefsListener)
        } catch (_: Exception) {}
        if (dismissOverlayView != null) {
            try {
                windowManager.removeView(dismissOverlayView)
            } catch (_: Exception) {}
            dismissOverlayView = null
        }
        if (::floatingView.isInitialized) {
            try {
                windowManager.removeView(floatingView)
            } catch (_: Exception) {}
        }
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()

        sendResultToActivity("stopped", 999, "Service stopped")
    }
}
