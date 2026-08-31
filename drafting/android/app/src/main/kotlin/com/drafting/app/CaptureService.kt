package com.drafting.app

import android.app.Notification
import com.drafting.app.R
import com.drafting.app.BuildConfig
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
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

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
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
        baseUrl = intent.getStringExtra("baseUrl")
        sessionToken = intent.getStringExtra("sessionToken")
        mainRole = intent.getStringExtra("mainRole")
        secondaryRole = intent.getStringExtra("secondaryRole")
        autofillRole = intent.getStringExtra("autofillRole")
        isPremium = intent.getBooleanExtra("isPremium", false)
        planTier = intent.getStringExtra("planTier") ?: "plus"
        otpChampions = intent.getStringExtra("otpChampions") ?: ""
        activeCreatorId = intent.getStringExtra("activeCreatorId")

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

        val btnCaptureAutofill = floatingView.findViewById<ImageButton>(R.id.btnCaptureAutofill)
        val btnCaptureOTP = floatingView.findViewById<ImageButton>(R.id.btnCaptureOTP)
        val btnCaptureInGame = floatingView.findViewById<ImageButton>(R.id.btnCaptureInGame)
        val btnClose = floatingView.findViewById<ImageButton>(R.id.btnClose)

        val hasProOrUltra = planTier == "pro" || planTier == "ultra"

        if (!hasProOrUltra) {
            btnCaptureOTP.setImageResource(android.R.drawable.ic_secure)
            btnCaptureInGame.setImageResource(android.R.drawable.ic_secure)
        }

        btnCaptureAutofill.setOnClickListener {
            captureScreenAndSend("autofill", 0)
        }
        
        btnCaptureOTP.setOnClickListener {
            if (hasProOrUltra) {
                captureScreenAndSend("otp", 0)
            } else {
                sendResultToActivity("PAYMENT_REQUIRED", 402, "Premium required")
                Toast.makeText(this, "Requiere plan Pro o Ultra", Toast.LENGTH_SHORT).show()
            }
        }
        
        btnCaptureInGame.setOnClickListener {
            if (hasProOrUltra) {
                captureScreenAndSend("in_game", 0)
            } else {
                sendResultToActivity("PAYMENT_REQUIRED", 402, "Premium required")
                Toast.makeText(this, "Requiere plan Pro o Ultra", Toast.LENGTH_SHORT).show()
            }
        }
        
        btnClose.setOnClickListener {
            stopSelf()
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
        params.x = 0
        params.y = 100

        val dragHandle = floatingView.findViewById<ImageView>(R.id.dragHandle)
        val messageContainer = floatingView.findViewById<FrameLayout>(R.id.messageContainer)
        
        setupDrag(dragHandle, params)
        setupDrag(messageContainer, params)

        try {
            windowManager.addView(floatingView, params)
        } catch (e: Exception) {
            notifyCaptureError("Overlay view could not be displayed: ${e.message}")
            stopSelf()
        }
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
                        }
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        params.x = initialX + (event.rawX - initialTouchX).toInt()
                        params.y = initialY + (event.rawY - initialTouchY).toInt()
                        windowManager.updateViewLayout(floatingView, params)
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
        
        // Escalar imagen para no colapsar la red y ahorrar tokens (máx 720p aprox)
        val maxDim = 1280.0f
        val scale = if (croppedBitmap.width > maxDim || croppedBitmap.height > maxDim) {
            Math.min(maxDim / croppedBitmap.width, maxDim / croppedBitmap.height)
        } else {
            1.0f
        }
        val scaledWidth = (croppedBitmap.width * scale).toInt()
        val scaledHeight = (croppedBitmap.height * scale).toInt()
        val finalBitmap = Bitmap.createScaledBitmap(croppedBitmap, scaledWidth, scaledHeight, true)

        // Compress and encode
        val stream = ByteArrayOutputStream()
        finalBitmap.compress(Bitmap.CompressFormat.JPEG, 60, stream)
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

    private fun sendToBackend(base64Image: String, queryType: String) {
        showToast("Analizando...")
        thread {
            try {
                val base = (baseUrl?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() }
                    ?: BuildConfig.BASE_URL.trimEnd('/'))
                if (base.isEmpty()) {
                    throw IllegalStateException("BASE_URL is not configured")
                }

                val url = URL("$base/api/v1/draft/analyze")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                if (!sessionToken.isNullOrEmpty()) {
                    conn.setRequestProperty("Authorization", "Bearer $sessionToken")
                }
                conn.connectTimeout = 30000
                conn.readTimeout = 30000
                conn.doOutput = true
                conn.doInput = true

                val jsonParam = JSONObject()
                jsonParam.put("image_base64", base64Image)
                jsonParam.put("main_role", mainRole)
                jsonParam.put("secondary_role", secondaryRole)
                jsonParam.put("autofill_role", autofillRole)
                jsonParam.put("query_type", queryType)
                jsonParam.put("otp_champions", otpChampions)
                if (activeCreatorId != null && activeCreatorId!!.isNotEmpty()) {
                    jsonParam.put("active_creator_id", activeCreatorId)
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
                    showResultOnUI(rec)
                    sendResultToActivity("success", 200, rec)
                } else if (responseCode == 429) {
                    showResultOnUI("Debes esperar 20 minutos para otra consulta.")
                    sendResultToActivity("error", 429, "Debes esperar 20 minutos.")
                } else if (responseCode == 402) {
                    showResultOnUI("Tu suscripción o prueba ha expirado.")
                    sendResultToActivity("error", 402, "Suscripción o prueba agotada.")
                } else {
                    val errorResponse = try {
                        conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                    } catch (e: Exception) { "" }
                    
                    val displayMsg = if (errorResponse.isNotEmpty()) "Error 500: $errorResponse" else "Error del servidor: $responseCode"
                    showResultOnUI(displayMsg)
                    sendResultToActivity("error", responseCode, displayMsg)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                showResultOnUI("Err: ${e.javaClass.simpleName} - ${e.message}")
                sendResultToActivity("error", 500, "Error de red: ${e.message}")
            }
        }
    }

    private fun showResultOnUI(text: String) {
        Handler(Looper.getMainLooper()).post {
            if (!::floatingView.isInitialized) return@post
            floatingView.findViewById<FrameLayout>(R.id.messageContainer).visibility = View.VISIBLE
            floatingView.findViewById<LinearLayout>(R.id.loadingLayout).visibility = View.GONE
            floatingView.findViewById<ScrollView>(R.id.resultScrollView).visibility = View.VISIBLE
            floatingView.findViewById<TextView>(R.id.resultTextView).text = text
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
    }
}
