package com.drafting.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.os.Bundle
import android.os.PowerManager
import android.content.pm.PackageManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Notification
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.drafting.app/capture"
    private val EVENT_CHANNEL = "com.drafting.app/events"
    private var eventSink: EventChannel.EventSink? = null
    private val REQUEST_CODE_SCREEN_CAPTURE = 1000
    private val REQUEST_CODE_OVERLAY = 1001
    private val REQUEST_CODE_NOTIFICATIONS = 1002
    private val REQUEST_CODE_IN_APP_UPDATE = 1003

    private var appUpdateManager: AppUpdateManager? = null

    private val installStateListener = InstallStateUpdatedListener { state ->
        try {
            when (state.installStatus()) {
                InstallStatus.DOWNLOADING -> {
                    val downloaded = state.bytesDownloaded()
                    val total = state.totalBytesToDownload()
                    val progress = if (total > 0) ((downloaded * 100) / total).toInt() else 0
                    eventSink?.success(
                        mapOf(
                            "status" to "UPDATE_DOWNLOADING",
                            "code" to 204,
                            "progress" to progress,
                            "message" to "Downloading update ($progress%)"
                        )
                    )
                }
                InstallStatus.DOWNLOADED -> {
                    eventSink?.success(
                        mapOf(
                            "status" to "UPDATE_DOWNLOADED",
                            "code" to 205,
                            "message" to "Update downloaded in background"
                        )
                    )
                }
                else -> {}
            }
        } catch (_: Exception) {}
    }

    private var pendingBaseUrl: String? = null
    private var pendingSessionToken: String? = null
    private var pendingMainRole: String? = null
    private var pendingSecondaryRole: String? = null
    private var pendingAutofillRole: String? = null
    private var pendingIsPremium: Boolean = false
    private var pendingPlanTier: String? = "plus"
    private var pendingOtpChampions: String? = ""
    private var pendingActiveCreatorId: String? = ""
    private var pendingLanguage: String? = "es"
    private var awaitingOverlayPermission: Boolean = false

    private val resultReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.drafting.app.RESULT_ACTION") {
                val status = intent.getStringExtra("status")
                val code = intent.getIntExtra("code", 0)
                val message = intent.getStringExtra("message")
                
                val data = mapOf(
                    "status" to status,
                    "code" to code,
                    "message" to message
                )
                eventSink?.success(data)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        savedInstanceState?.let {
            pendingBaseUrl = it.getString("pendingBaseUrl")
            pendingSessionToken = it.getString("pendingSessionToken")
            pendingMainRole = it.getString("pendingMainRole")
            pendingSecondaryRole = it.getString("pendingSecondaryRole")
            pendingAutofillRole = it.getString("pendingAutofillRole")
            pendingIsPremium = it.getBoolean("pendingIsPremium", false)
            pendingPlanTier = it.getString("pendingPlanTier", "plus")
            pendingOtpChampions = it.getString("pendingOtpChampions", "")
            pendingActiveCreatorId = it.getString("pendingActiveCreatorId", "")
            awaitingOverlayPermission = it.getBoolean("awaitingOverlayPermission", false)
        }

        try {
            val filter = IntentFilter("com.drafting.app.RESULT_ACTION")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(resultReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(resultReceiver, filter)
            }
        } catch (_: Exception) {}

        try {
            appUpdateManager = AppUpdateManagerFactory.create(applicationContext)
            appUpdateManager?.registerListener(installStateListener)
        } catch (_: Exception) {}
    }

    override fun onResume() {
        super.onResume()
        try {
            val manager = appUpdateManager ?: AppUpdateManagerFactory.create(applicationContext).also {
                appUpdateManager = it
            }
            manager.appUpdateInfo.addOnSuccessListener { info ->
                if (info.installStatus() == InstallStatus.DOWNLOADED) {
                    eventSink?.success(
                        mapOf(
                            "status" to "UPDATE_DOWNLOADED",
                            "code" to 205,
                            "message" to "Update downloaded in background"
                        )
                    )
                } else if (info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS) {
                    if (info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)) {
                        manager.startUpdateFlowForResult(
                            info,
                            this,
                            AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(),
                            REQUEST_CODE_IN_APP_UPDATE
                        )
                    }
                }
            }
        } catch (_: Exception) {}
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("pendingBaseUrl", pendingBaseUrl)
        outState.putString("pendingSessionToken", pendingSessionToken)
        outState.putString("pendingMainRole", pendingMainRole)
        outState.putString("pendingSecondaryRole", pendingSecondaryRole)
        outState.putString("pendingAutofillRole", pendingAutofillRole)
        outState.putBoolean("pendingIsPremium", pendingIsPremium)
        outState.putString("pendingPlanTier", pendingPlanTier)
        outState.putString("pendingOtpChampions", pendingOtpChampions)
        outState.putString("pendingActiveCreatorId", pendingActiveCreatorId)
        outState.putBoolean("awaitingOverlayPermission", awaitingOverlayPermission)
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(resultReceiver)
        } catch (_: Exception) {}
        try {
            appUpdateManager?.unregisterListener(installStateListener)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startService") {
                pendingBaseUrl = call.argument("baseUrl")
                pendingSessionToken = call.argument("sessionToken")
                pendingMainRole = call.argument("mainRole")
                pendingSecondaryRole = call.argument("secondaryRole")
                pendingAutofillRole = call.argument("autofillRole")
                pendingIsPremium = call.argument("isPremium") ?: false
                pendingPlanTier = call.argument("planTier") ?: "plus"
                pendingOtpChampions = call.argument("otpChampions") ?: ""
                pendingActiveCreatorId = call.argument("activeCreatorId") ?: ""
                pendingLanguage = call.argument("language") ?: "es"
                getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).edit()
                    .putString("language", pendingLanguage?.lowercase()?.take(2) ?: "es")
                    .apply()

                if (!Settings.canDrawOverlays(this)) {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    awaitingOverlayPermission = true
                    startActivityForResult(intent, REQUEST_CODE_OVERLAY)
                    result.error("PERMISSION_DENIED", "Overlay permission required", null)
                    return@setMethodCallHandler
                }

                startMediaProjectionRequest()
                result.success(true)
            } else if (call.method == "stopService") {
                val intent = Intent(this, CaptureService::class.java)
                stopService(intent)
                result.success(true)
            } else if (call.method == "isIgnoringBatteryOptimizations") {
                val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    pm?.isIgnoringBatteryOptimizations(packageName) ?: true
                } else {
                    true
                }
                result.success(isIgnoring)
            } else if (call.method == "requestIgnoreBatteryOptimizations") {
                var requested = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    try {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        requested = true
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                            requested = true
                        } catch (_: Exception) {}
                    }
                }
                result.success(requested)
            } else if (call.method == "getAppVersion") {
                try {
                    val pInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
                    } else {
                        @Suppress("DEPRECATION")
                        packageManager.getPackageInfo(packageName, 0)
                    }
                    val vCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        pInfo.longVersionCode.toInt()
                    } else {
                        @Suppress("DEPRECATION")
                        pInfo.versionCode
                    }
                    val vName = pInfo.versionName ?: BuildConfig.VERSION_NAME
                    result.success(mapOf(
                        "versionCode" to vCode,
                        "versionName" to vName,
                        "packageName" to packageName
                    ))
                } catch (e: Exception) {
                    result.success(mapOf(
                        "versionCode" to BuildConfig.VERSION_CODE,
                        "versionName" to BuildConfig.VERSION_NAME,
                        "packageName" to packageName
                    ))
                }
            } else if (call.method == "checkPlayInAppUpdate") {
                try {
                    val manager = appUpdateManager ?: AppUpdateManagerFactory.create(applicationContext).also {
                        appUpdateManager = it
                    }
                    manager.appUpdateInfo
                        .addOnSuccessListener { info ->
                            val avail = info.updateAvailability()
                            val hasUpdate = avail == UpdateAvailability.UPDATE_AVAILABLE ||
                                    avail == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
                            val isDownloaded = info.installStatus() == InstallStatus.DOWNLOADED
                            result.success(
                                mapOf(
                                    "updateAvailable" to (hasUpdate || isDownloaded),
                                    "availableVersionCode" to info.availableVersionCode(),
                                    "flexibleAllowed" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                                    "immediateAllowed" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
                                    "installStatus" to info.installStatus(),
                                    "isDownloaded" to isDownloaded
                                )
                            )
                        }
                        .addOnFailureListener {
                            result.success(
                                mapOf(
                                    "updateAvailable" to false,
                                    "availableVersionCode" to 0,
                                    "flexibleAllowed" to false,
                                    "immediateAllowed" to false,
                                    "installStatus" to 0,
                                    "isDownloaded" to false
                                )
                            )
                        }
                } catch (_: Exception) {
                    result.success(
                        mapOf(
                            "updateAvailable" to false,
                            "availableVersionCode" to 0,
                            "flexibleAllowed" to false,
                            "immediateAllowed" to false,
                            "installStatus" to 0,
                            "isDownloaded" to false
                        )
                    )
                }
            } else if (call.method == "startInAppUpdate") {
                val mode = (call.argument<String>("mode") ?: "flexible").lowercase()
                val openStoreFallback = call.argument<Boolean>("openStoreFallback") ?: true
                val customUrl = call.argument<String>("url")
                try {
                    val manager = appUpdateManager ?: AppUpdateManagerFactory.create(applicationContext).also {
                        appUpdateManager = it
                    }
                    manager.appUpdateInfo
                        .addOnSuccessListener { info ->
                            try {
                                if (info.installStatus() == InstallStatus.DOWNLOADED) {
                                    manager.completeUpdate()
                                    result.success(mapOf("started" to true, "method" to "complete_downloaded"))
                                    return@addOnSuccessListener
                                }
                                val avail = info.updateAvailability()
                                val canStart = avail == UpdateAvailability.UPDATE_AVAILABLE ||
                                        avail == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
                                if (canStart) {
                                    val updateType = if (mode == "immediate" && info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)) {
                                        AppUpdateType.IMMEDIATE
                                    } else if (info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)) {
                                        AppUpdateType.FLEXIBLE
                                    } else if (info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)) {
                                        AppUpdateType.IMMEDIATE
                                    } else {
                                        -1
                                    }
                                    if (updateType != -1) {
                                        val started = manager.startUpdateFlowForResult(
                                            info,
                                            this,
                                            AppUpdateOptions.newBuilder(updateType).build(),
                                            REQUEST_CODE_IN_APP_UPDATE
                                        )
                                        if (started) {
                                            result.success(mapOf("started" to true, "method" to "in_app_update"))
                                            return@addOnSuccessListener
                                        }
                                    }
                                }
                            } catch (_: Exception) {}

                            if (openStoreFallback) {
                                val opened = openPlayStoreMarket(customUrl)
                                result.success(mapOf("started" to opened, "method" to "play_store_intent"))
                            } else {
                                result.success(mapOf("started" to false, "method" to "none"))
                            }
                        }
                        .addOnFailureListener {
                            if (openStoreFallback) {
                                val opened = openPlayStoreMarket(customUrl)
                                result.success(mapOf("started" to opened, "method" to "play_store_intent"))
                            } else {
                                result.success(mapOf("started" to false, "method" to "none"))
                            }
                        }
                } catch (_: Exception) {
                    if (openStoreFallback) {
                        val opened = openPlayStoreMarket(customUrl)
                        result.success(mapOf("started" to opened, "method" to "play_store_intent"))
                    } else {
                        result.success(mapOf("started" to false, "method" to "none"))
                    }
                }
            } else if (call.method == "completeInAppUpdate") {
                try {
                    appUpdateManager?.completeUpdate()
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            } else if (call.method == "openPlayStoreUpdate") {
                val customUrl = call.argument<String>("url")
                val opened = openPlayStoreMarket(customUrl)
                result.success(opened)
            } else if (call.method == "openExternalUrl") {
                val rawUrl = (call.argument<String>("url") ?: "").trim()
                if (rawUrl.isBlank()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                val normalizedUrl = if (
                    rawUrl.startsWith("http://", ignoreCase = true) ||
                    rawUrl.startsWith("https://", ignoreCase = true) ||
                    rawUrl.startsWith("market://", ignoreCase = true)
                ) {
                    rawUrl
                } else {
                    "https://${rawUrl.trimStart('/')}"
                }
                var launched = false
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(normalizedUrl)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    launched = true
                } catch (_: Exception) {}
                result.success(launched)
            } else if (call.method == "areNotificationsEnabled") {
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                val enabledByManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    nm?.areNotificationsEnabled() ?: true
                } else {
                    true
                }
                val hasRuntimePerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                } else {
                    true
                }
                result.success(enabledByManager && hasRuntimePerm)
            } else if (call.method == "requestNotificationPermission") {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE_NOTIFICATIONS)
                            result.success(true)
                            return@setMethodCallHandler
                        }
                    }
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    val enabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        nm?.areNotificationsEnabled() ?: true
                    } else {
                        true
                    }
                    if (!enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val settingsIntent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        startActivity(settingsIntent)
                    }
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            } else if (call.method == "setLanguage") {
                val lang = (call.argument<String>("language") ?: "es").lowercase().take(2)
                pendingLanguage = lang
                getSharedPreferences("drafting_prefs", Context.MODE_PRIVATE).edit()
                    .putString("language", lang)
                    .apply()
                result.success(true)
            } else if (call.method == "showEventNotification") {
                val title = call.argument<String>("title") ?: "Drafting"
                val body = call.argument<String>("body") ?: ""
                val targetUrl = call.argument<String>("url") ?: ""
                showNativeEventNotification(title, body, targetUrl)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun openPlayStoreMarket(customUrl: String?): Boolean {
        val targetPkg = packageName
        var opened = false
        try {
            val marketIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("market://details?id=$targetPkg")
            ).apply {
                setPackage("com.android.vending")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            startActivity(marketIntent)
            opened = true
        } catch (_: Exception) {
            try {
                val fallbackUri = if (!customUrl.isNullOrBlank()) {
                    Uri.parse(customUrl)
                } else {
                    Uri.parse("https://play.google.com/store/apps/details?id=$targetPkg")
                }
                val webIntent = Intent(Intent.ACTION_VIEW, fallbackUri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(webIntent)
                opened = true
            } catch (_: Exception) {}
        }
        return opened
    }

    private fun showNativeEventNotification(title: String, body: String, targetUrl: String) {
        try {
            val channelId = "DraftingLiveEventsChannel"
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Directos y Eventos Oficiales",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Alertas cuando Drafting está en directo o inicia un evento"
                }
                nm.createNotificationChannel(channel)
            }

            val trimmedUrl = targetUrl.trim()
            val clickIntent = if (trimmedUrl.isNotBlank()) {
                val safeUrl = if (
                    trimmedUrl.startsWith("http://", ignoreCase = true) ||
                    trimmedUrl.startsWith("https://", ignoreCase = true)
                ) {
                    trimmedUrl
                } else {
                    "https://${trimmedUrl.trimStart('/')}"
                }
                Intent(Intent.ACTION_VIEW, Uri.parse(safeUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            } else {
                Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
            }

            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getActivity(this, 202, clickIntent, pendingFlags)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            val notification = builder
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .build()

            nm.notify(202, notification)
        } catch (_: Exception) {}
    }

    private fun startMediaProjectionRequest() {
        val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(mediaProjectionManager.createScreenCaptureIntent(), REQUEST_CODE_SCREEN_CAPTURE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_CODE_OVERLAY) {
            awaitingOverlayPermission = false
            if (Settings.canDrawOverlays(this)) {
                startMediaProjectionRequest()
            } else {
                eventSink?.error("PERMISSION_DENIED", "Overlay permission not granted", null)
            }
        } else if (requestCode == REQUEST_CODE_SCREEN_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val serviceIntent = Intent(this, CaptureService::class.java)
                serviceIntent.putExtra("code", resultCode)
                serviceIntent.putExtra("data", data)
                serviceIntent.putExtra("baseUrl", pendingBaseUrl)
                serviceIntent.putExtra("sessionToken", pendingSessionToken)
                serviceIntent.putExtra("mainRole", pendingMainRole)
                serviceIntent.putExtra("secondaryRole", pendingSecondaryRole)
                serviceIntent.putExtra("autofillRole", pendingAutofillRole)
                serviceIntent.putExtra("isPremium", pendingIsPremium)
                serviceIntent.putExtra("planTier", pendingPlanTier)
                serviceIntent.putExtra("otpChampions", pendingOtpChampions)
                serviceIntent.putExtra("activeCreatorId", pendingActiveCreatorId)
                serviceIntent.putExtra("language", pendingLanguage)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
            } else {
                eventSink?.error("PERMISSION_DENIED", "Screen capture permission denied", null)
            }
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
