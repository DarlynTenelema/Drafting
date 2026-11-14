package com.drafting.app

import android.app.Notification
import com.drafting.app.R
import com.drafting.app.BuildConfig
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Base64
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ScrollView
import android.widget.TextView
import android.widget.LinearLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.FrameLayout
import android.net.ConnectivityManager
import android.widget.Toast
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class CaptureService : Service() {
    private val NOTIFICATION_ID = 101
    private val CHANNEL_ID = "DraftingCaptureChannel"

    private lateinit var windowManager: WindowManager
    private lateinit var floatingView: View
    
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    
    private var baseUrl: String? = null
    private var sessionToken: String? = null
    private var mainRole: String? = null
    private var secondaryRole: String? = null
    private var autofillRole: String? = null
    private var isPremium: Boolean = false
    private var planTier: String = "plus"
    private var otpChampions: String = ""
    private var activeCreatorId: String? = null
    private var language: String = "es"
    private var lastCapturedBase64: String? = null
    private val seenChampionsInDraft = mutableListOf<String>()

    private val prefsListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { sharedPrefs, key ->
        if (key == "language") {
            val updated = sharedPrefs.getString("language", "es") ?: "es"
            language = updated.lowercase().take(2)
            Handler(Looper.getMainLooper()).post {
                refreshOverlayTexts()
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
    }

    private fun overlayTr(key: String): String {
        val lang = getCurrentLang()
        return when (lang) {
            "pt" -> when (key) {
                "title" -> "RECOMENDAÇÃO IA"
                "analyzing_match" -> "Analisando partida..."
                "reconsulting" -> "Consultando alternativas..."
                "analyzing_toast" -> "Analisando..."
                "copied" -> "Recomendação copiada para a área de transferência!"
                "view_translucent" -> "Visão: Translúcida (65%)"
                "view_solid" -> "Visão: Sólida (94%)"
                "size_compact" -> "Tamanho: Compacto"
                "size_standard" -> "Tamanho: Padrão"
                "size_wide" -> "Tamanho: Amplo"
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
                "reconsulting" -> "Refreshing alternatives..."
                "analyzing_toast" -> "Analyzing..."
                "copied" -> "Recommendation copied to clipboard!"
                "view_translucent" -> "View: Translucent (65%)"
                "view_solid" -> "View: Solid (94%)"
                "size_compact" -> "Size: Compact"
                "size_standard" -> "Size: Standard"
                "size_wide" -> "Size: Wide"
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
                "analyzing_toast" -> "Analyse en cours..."
                "copied" -> "Recommandation copiée dans le presse-papiers !"
                "view_translucent" -> "Vue : Translucide (65%)"
                "view_solid" -> "Vue : Solide (94%)"
                "size_compact" -> "Taille : Compacte"
                "size_standard" -> "Taille : Standard"
                "size_wide" -> "Taille : Large"
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
                "reconsulting" -> "Consultando alternativas..."
                "analyzing_toast" -> "Analizando..."
                "copied" -> "¡Recomendación copiada al portapapeles!"
                "view_translucent" -> "Vista: Traslúcida (65%)"
                "view_solid" -> "Vista: Sólida (94%)"
                "size_compact" -> "Tamaño: Compacto"
                "size_standard" -> "Tamaño: Estándar"
                "size_wide" -> "Tamaño: Amplio"
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
        mainRole = intent.getStringExtra("mainRole")
        secondaryRole = intent.getStringExtra("secondaryRole")
        autofillRole = intent.getStringExtra("autofillRole")
        isPremium = intent.getBooleanExtra("isPremium", false)
        planTier = intent.getStringExtra("planTier") ?: "plus"
        otpChampions = intent.getStringExtra("otpChampions") ?: ""
        activeCreatorId = intent.getStringExtra("activeCreatorId")
        val incomingLang = intent.getStringExtra("language")
        if (!incomingLang.isNullOrBlank()) {
            language = incomingLang.lowercase().take(2)
            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).edit().putString("language", language).apply()
        } else {
            language = getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).getString("language", "es") ?: "es"
        }

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
        
        // Postpone projection creation slightly to ensure startForeground is fully processed by Android 14
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                mediaProjection = mpm.getMediaProjection(code, data)
                if (mediaProjection == null) {
                    notifyCaptureError("MediaProjection is null.")
                    stopSelf()
                    return@postDelayed
                }

                // Android 14 requires a callback to be registered
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
            } catch (e: Exception) {
                // Ignore if not attached
            }
        }

        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        floatingView = inflater.inflate(R.layout.layout_overlay, null)

        val expandedContainer = floatingView.findViewById<LinearLayout>(R.id.expandedContainer)
        val btnCollapsedBubble = floatingView.findViewById<ImageButton>(R.id.btnCollapsedBubble)
        val btnMinimize = floatingView.findViewById<ImageButton>(R.id.btnMinimize)

        val btnCaptureGeneral = floatingView.findViewById<ImageButton>(R.id.btnCaptureGeneral)
        val btnClose = floatingView.findViewById<ImageButton>(R.id.btnClose)
        val btnCloseMessage = floatingView.findViewById<ImageButton>(R.id.btnCloseMessage)
        val btnCopyMessage = floatingView.findViewById<ImageButton>(R.id.btnCopyMessage)
        val btnRefreshDraft = floatingView.findViewById<ImageButton>(R.id.btnRefreshDraft)

        btnCaptureGeneral?.setOnClickListener {
            seenChampionsInDraft.clear()
            captureScreenAndSend("draft", 0)
        }

        btnRefreshDraft?.setOnClickListener {
            if (lastCapturedBase64 != null) {
                Handler(Looper.getMainLooper()).post {
                    refreshOverlayTexts()
                    floatingView.findViewById<TextView>(R.id.loadingTextView)?.text = overlayTr("reconsulting")
                    adjustMessageContainerPosition()
                    floatingView.findViewById<FrameLayout>(R.id.messageContainer).visibility = View.VISIBLE
                    floatingView.findViewById<LinearLayout>(R.id.loadingLayout).visibility = View.VISIBLE
                    floatingView.findViewById<ScrollView>(R.id.resultScrollView).visibility = View.GONE
                }
                sendToBackend(lastCapturedBase64!!, "draft", seenChampionsInDraft.joinToString(", "))
            } else {
                seenChampionsInDraft.clear()
                captureScreenAndSend("draft", 0)
            }
        }
        
        btnMinimize.setOnClickListener {
            // Oculta el contenedor expandido y muestra la burbuja miniatura
            expandedContainer.visibility = View.GONE
            floatingView.findViewById<FrameLayout>(R.id.messageContainer).visibility = View.GONE
            btnCollapsedBubble.visibility = View.VISIBLE
        }

        btnCollapsedBubble.setOnClickListener {
            // Muestra el contenedor expandido y oculta la burbuja
            btnCollapsedBubble.visibility = View.GONE
            expandedContainer.visibility = View.VISIBLE
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

        btnCloseMessage?.setOnClickListener {
            // Cierra únicamente el panel de recomendación sin ocultar los controles
            floatingView.findViewById<FrameLayout>(R.id.messageContainer).visibility = View.GONE
        }

        btnClose.setOnClickListener {
            stopSelf()
        }

        val messageContainer = floatingView.findViewById<FrameLayout>(R.id.messageContainer)
        val btnToggleOpacity = floatingView.findViewById<ImageButton>(R.id.btnToggleOpacity)
        val btnToggleSize = floatingView.findViewById<ImageButton>(R.id.btnToggleSize)
        val btnResizeCorner = floatingView.findViewById<ImageView>(R.id.btnResizeCorner)
        val prefs = getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE)

        // Botones de Rol en Vivo (TOP, JG, MID, ADC, SUP, AUTO)
        val btnRoleTop = floatingView.findViewById<TextView>(R.id.btnRoleTop)
        val btnRoleJg = floatingView.findViewById<TextView>(R.id.btnRoleJg)
        val btnRoleMid = floatingView.findViewById<TextView>(R.id.btnRoleMid)
        val btnRoleAdc = floatingView.findViewById<TextView>(R.id.btnRoleAdc)
        val btnRoleSup = floatingView.findViewById<TextView>(R.id.btnRoleSup)
        val btnRoleAuto = floatingView.findViewById<TextView>(R.id.btnRoleAuto)

        val roleButtons = mapOf(
            "Top" to btnRoleTop,
            "Jungle" to btnRoleJg,
            "Mid" to btnRoleMid,
            "ADC" to btnRoleAdc,
            "Support" to btnRoleSup,
            "Auto" to btnRoleAuto
        )

        fun updateRoleButtonsUI(selectedRole: String?) {
            val norm = when (selectedRole?.lowercase()?.trim()) {
                "top", "baron", "solo" -> "Top"
                "jg", "jungle", "jungla" -> "Jungle"
                "mid", "middle" -> "Mid"
                "adc", "duo", "bot", "bottom" -> "ADC"
                "sup", "support", "soporte" -> "Support"
                else -> "Auto"
            }
            roleButtons.forEach { (roleKey, btn) ->
                if (btn == null) return@forEach
                if (roleKey == norm) {
                    btn.setBackgroundResource(R.drawable.bg_role_btn_active)
                    btn.setTextColor(Color.parseColor("#090D16"))
                } else {
                    btn.setBackgroundResource(R.drawable.bg_role_btn)
                    btn.setTextColor(Color.parseColor("#CBD5E1"))
                }
            }
        }

        val initialRole = if (!mainRole.isNullOrBlank()) mainRole else prefs.getString("main_role", "Auto") ?: "Auto"
        mainRole = initialRole
        updateRoleButtonsUI(initialRole)

        fun onRoleSelected(role: String) {
            mainRole = role
            updateRoleButtonsUI(role)
            prefs.edit().putString("main_role", role).apply()
            showToast("Rol: $role")

            // Si el contenedor de recomendación está visible y ya capturamos, reanalizar automáticamente con el nuevo rol
            val msgCard = floatingView.findViewById<FrameLayout>(R.id.messageContainer)
            if (msgCard?.visibility == View.VISIBLE && lastCapturedBase64 != null) {
                Handler(Looper.getMainLooper()).post {
                    refreshOverlayTexts()
                    floatingView.findViewById<TextView>(R.id.loadingTextView)?.text = overlayTr("analyzing_match")
                    adjustMessageContainerPosition()
                    floatingView.findViewById<LinearLayout>(R.id.loadingLayout).visibility = View.VISIBLE
                    floatingView.findViewById<ScrollView>(R.id.resultScrollView).visibility = View.GONE
                }
                sendToBackend(lastCapturedBase64!!, "draft", "")
            }
        }

        btnRoleTop?.setOnClickListener { onRoleSelected("Top") }
        btnRoleJg?.setOnClickListener { onRoleSelected("Jungle") }
        btnRoleMid?.setOnClickListener { onRoleSelected("Mid") }
        btnRoleAdc?.setOnClickListener { onRoleSelected("ADC") }
        btnRoleSup?.setOnClickListener { onRoleSelected("Support") }
        btnRoleAuto?.setOnClickListener { onRoleSelected("Auto") }

        // 1. Restaurar Opacidad guardada
        var isLowOpacity = prefs.getBoolean("overlay_low_opacity", false)
        messageContainer?.alpha = if (isLowOpacity) 0.65f else 0.94f

        btnToggleOpacity?.setOnClickListener {
            isLowOpacity = !isLowOpacity
            messageContainer?.alpha = if (isLowOpacity) 0.65f else 0.94f
            prefs.edit().putBoolean("overlay_low_opacity", isLowOpacity).apply()
            showToast(if (isLowOpacity) overlayTr("view_translucent") else overlayTr("view_solid"))
        }

        val layoutFlag: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )

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
            } catch (e: Exception) {
                // Ignore
            }
        }

        var sizeIndex = prefs.getInt("overlay_size_index", 1)
        val savedCustomWidth = prefs.getInt("overlay_custom_width", 0)
        val savedCustomHeight = prefs.getInt("overlay_custom_height", 0)

        if (savedCustomWidth > 0 && savedCustomHeight > 0) {
            applyContainerSize(savedCustomWidth, savedCustomHeight)
        } else {
            val (wDp, hDp) = when (sizeIndex) {
                0 -> Pair(280, 170)
                2 -> Pair(420, 310)
                else -> Pair(340, 230)
            }
            applyContainerSize(dpToPx(wDp), dpToPx(hDp))
        }

        btnToggleSize?.setOnClickListener {
            sizeIndex = (sizeIndex + 1) % 3
            prefs.edit().putInt("overlay_size_index", sizeIndex)
                .remove("overlay_custom_width")
                .remove("overlay_custom_height").apply()
            val (wDp, hDp, label) = when (sizeIndex) {
                0 -> Triple(280, 170, overlayTr("size_compact"))
                2 -> Triple(420, 310, overlayTr("size_wide"))
                else -> Triple(340, 230, overlayTr("size_standard"))
            }
            applyContainerSize(dpToPx(wDp), dpToPx(hDp))
            showToast(label)
        }

        // 3. Redimensionar libremente arrastrando con el dedo desde la esquina
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
                        val minW = dpToPx(240)
                        val minH = dpToPx(140)
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

        val dragHandle = floatingView.findViewById<ImageView>(R.id.dragHandle)
        val messageTitle = floatingView.findViewById<TextView>(R.id.messageTitle)
        val loadingTextView = floatingView.findViewById<TextView>(R.id.loadingTextView)
        messageTitle?.text = overlayTr("title")
        loadingTextView?.text = overlayTr("analyzing_match")
        
        setupDrag(dragHandle, params)
        if (messageTitle != null) {
            setupDrag(messageTitle, params)
        }
        setupDrag(btnCollapsedBubble, params)

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

    private fun setupDrag(view: View, params: WindowManager.LayoutParams) {
        view.setOnTouchListener(object : View.OnTouchListener {
            private var initialX: Int = 0
            private var initialY: Int = 0
            private var initialTouchX: Float = 0f
            private var initialTouchY: Float = 0f
            private val CLICK_DRAG_TOLERANCE = 10f

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        if (Math.abs(dx) < CLICK_DRAG_TOLERANCE && Math.abs(dy) < CLICK_DRAG_TOLERANCE) {
                            v.performClick()
                        } else {
                            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).edit()
                                .putInt("overlay_pos_x", params.x)
                                .putInt("overlay_pos_y", params.y).apply()
                            adjustMessageContainerPosition()
                        }
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        params.x = initialX + (event.rawX - initialTouchX).toInt()
                        params.y = initialY + (event.rawY - initialTouchY).toInt()
                        try {
                            windowManager.updateViewLayout(floatingView, params)
                        } catch (e: Exception) {
                            // Ignore
                        }
                        return true
                    }
                }
                return false
            }
        })
    }

    private fun captureScreenAndSend(queryType: String, retryCount: Int = 0) {
        // Show Loading State
        if (retryCount == 0) {
            Handler(Looper.getMainLooper()).post {
                refreshOverlayTexts()
                adjustMessageContainerPosition()
                floatingView.findViewById<FrameLayout>(R.id.messageContainer).visibility = View.VISIBLE
                floatingView.findViewById<LinearLayout>(R.id.loadingLayout).visibility = View.VISIBLE
                floatingView.findViewById<ScrollView>(R.id.resultScrollView).visibility = View.GONE
            }
        }

        try {
            val image = imageReader?.acquireLatestImage()

            if (image == null) {
                if (retryCount < 3) {
                    Handler(Looper.getMainLooper()).postDelayed({ captureScreenAndSend(queryType, retryCount + 1) }, 500)
                    return
                }
                notifyCaptureError("No image available from screen capture.")
                return
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
        
        // Remove padding to get exact screen bounds
        val croppedBitmap = Bitmap.createBitmap(bitmap, 0, 0, imgWidth, imgHeight)
        
        // Escalar proporcionalmente si supera 1600px para mantener textos nítidos sin enviar 8-10MB por red móvil
        val maxDimension = 1600
        val largestSide = maxOf(imgWidth, imgHeight)
        val finalBitmap = if (largestSide > maxDimension) {
            val scale = maxDimension.toFloat() / largestSide.toFloat()
            val targetW = (imgWidth * scale).toInt().coerceAtLeast(1)
            val targetH = (imgHeight * scale).toInt().coerceAtLeast(1)
            Bitmap.createScaledBitmap(croppedBitmap, targetW, targetH, true)
        } else {
            croppedBitmap
        }

        // Comprimir con alta nitidez (84%) reduciendo el peso un 90% para evitar timeouts
        val stream = ByteArrayOutputStream()
        finalBitmap.compress(Bitmap.CompressFormat.JPEG, 84, stream)
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

        // Buscar recomendaciones similares a partir de la cabecera correspondiente
        val simSectionIndex = text.indexOfAny(listOf("Recomendaciones similares:", "Recomendações semelhantes:", "Similar recommendations:", "Recommandations similaires:"), ignoreCase = true)
        val textToSearch = if (simSectionIndex != -1) text.substring(simSectionIndex) else text

        val patternSim = Regex("""•\s*([^:\n\r]+):""", RegexOption.IGNORE_CASE)
        patternSim.findAll(textToSearch).forEach { match ->
            val name = match.groupValues.getOrNull(1)?.trim() ?: ""
            if (name.isNotEmpty() && !seenChampionsInDraft.contains(name)) {
                val lower = name.lowercase()
                if (!lower.contains("hechizo") && !lower.contains("runa") && !lower.contains("plan") &&
                    !lower.contains("spell") && !lower.contains("feitiço") && !lower.contains("sort") &&
                    !lower.contains("sinerg") && !lower.contains("build") && !lower.contains("combo") &&
                    !lower.contains("táctica") && !lower.contains("tactica") && !lower.contains("objeto")) {
                    seenChampionsInDraft.add(name)
                }
            }
        }
    }

    private fun sendToBackend(base64Image: String, queryType: String, excludeChampions: String = "") {
        lastCapturedBase64 = base64Image
        showToast(overlayTr("analyzing_toast"))
        thread {
            val prefs = getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE)
            val currentLang = (prefs.getString("language", language) ?: language).lowercase().take(2)
            val base = (baseUrl?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() }
                ?: prefs.getString("base_url", null)?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() }
                ?: BuildConfig.BASE_URL.trimEnd('/'))
            if (base.isEmpty()) {
                showResultOnUI("Error: BASE_URL not configured.")
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
                    val url = URL("$base/api/v1/draft/analyze")
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

                    val jsonParam = JSONObject().apply {
                        put("image_base64", base64Image)
                        put("main_role", mainRole)
                        put("secondary_role", secondaryRole)
                        put("autofill_role", autofillRole)
                        put("query_type", queryType)
                        put("otp_champions", otpChampions)
                        put("language", currentLang)
                        if (excludeChampions.isNotBlank()) {
                            put("exclude_champions", excludeChampions)
                        }
                        if (!activeCreatorId.isNullOrEmpty()) {
                            put("active_creator_id", activeCreatorId)
                        }
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
                        val rec = jsonResponse.getString("recommendation")
                        extractChampionsFromRec(rec)
                        showResultOnUI(rec)
                        sendResultToActivity("success", 200, rec)
                        return@thread
                    } else if (responseCode == 429) {
                        showResultOnUI(overlayTr("err_429"))
                        sendResultToActivity("error", 429, overlayTr("err_429"))
                        return@thread
                    } else if (responseCode == 401) {
                        showResultOnUI(overlayTr("err_401"))
                        sendResultToActivity("error", 401, overlayTr("err_401"))
                        return@thread
                    } else if (responseCode == 402) {
                        showResultOnUI(overlayTr("err_402"))
                        sendResultToActivity("error", 402, overlayTr("err_402"))
                        return@thread
                    } else {
                        val errorResponse = try {
                            conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                        } catch (e: Exception) { "" }
                        
                        val displayMsg = if (errorResponse.isNotEmpty()) "Error 500: $errorResponse" else "Error: $responseCode"
                        showResultOnUI(displayMsg)
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
                showResultOnUI(friendlyMsg)
                sendResultToActivity("error", 500, friendlyMsg)
            }
        }
    }

    private fun showResultOnUI(text: String) {
        Handler(Looper.getMainLooper()).post {
            if (!::floatingView.isInitialized) return@post
            refreshOverlayTexts()
            adjustMessageContainerPosition()
            floatingView.findViewById<FrameLayout>(R.id.messageContainer).visibility = View.VISIBLE
            floatingView.findViewById<LinearLayout>(R.id.loadingLayout).visibility = View.GONE
            floatingView.findViewById<ScrollView>(R.id.resultScrollView).visibility = View.VISIBLE
            floatingView.findViewById<TextView>(R.id.resultTextView).text = text
        }
    }

    private fun adjustMessageContainerPosition() {
        if (!::floatingView.isInitialized) return
        val expandedContainer = floatingView.findViewById<LinearLayout>(R.id.expandedContainer) ?: return
        val messageContainer = floatingView.findViewById<FrameLayout>(R.id.messageContainer) ?: return
        val controlsContainer = floatingView.findViewById<LinearLayout>(R.id.controlsContainer) ?: return
        val rolesBarContainer = floatingView.findViewById<LinearLayout>(R.id.rolesBarContainer)
        val metrics = resources.displayMetrics
        val screenWidth = metrics.widthPixels
        
        val params = floatingView.layoutParams as? WindowManager.LayoutParams ?: return
        val marginPx = (10 * metrics.density).toInt()
        
        expandedContainer.removeAllViews()
        if (params.x < screenWidth / 2) {
            // Burbuja a la izquierda: Controles (izq) -> Mensaje (centro) -> Barra de Roles (der)
            expandedContainer.addView(controlsContainer)
            expandedContainer.addView(messageContainer)
            if (rolesBarContainer != null) {
                expandedContainer.addView(rolesBarContainer)
            }
            val layoutParams = messageContainer.layoutParams as LinearLayout.LayoutParams
            layoutParams.marginStart = marginPx
            layoutParams.marginEnd = 0
            messageContainer.layoutParams = layoutParams
        } else {
            // Burbuja a la derecha: Barra de Roles (izq) -> Mensaje (centro) -> Controles (der)
            if (rolesBarContainer != null) {
                expandedContainer.addView(rolesBarContainer)
            }
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
        showResultOnUI(message)
    }

    private fun showToastOnUIThread(msg: String) {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(applicationContext, msg, Toast.LENGTH_LONG).show()
        }
    }
    
    private fun showToast(msg: String) {
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen Capture Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Draft is running")
            .setContentText("Screen capture overlay active")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE)
                .unregisterOnSharedPreferenceChangeListener(prefsListener)
        } catch (_: Exception) {}
        if (::floatingView.isInitialized) {
            try {
                windowManager.removeView(floatingView)
            } catch (e: Exception) {
                // Ignore if not attached
            }
        }
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
        
        sendResultToActivity("stopped", 999, "Service stopped")
    }
}
