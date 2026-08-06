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

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.drafting.app/capture"
    private val EVENT_CHANNEL = "com.drafting.app/events"
    private var eventSink: EventChannel.EventSink? = null
    private val REQUEST_CODE_SCREEN_CAPTURE = 1000
    private val REQUEST_CODE_OVERLAY = 1001

    private var pendingBaseUrl: String? = null
    private var pendingSessionToken: String? = null
    private var pendingMainRole: String? = null
    private var pendingSecondaryRole: String? = null
    private var pendingAutofillRole: String? = null
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
        val filter = IntentFilter("com.drafting.app.RESULT_ACTION")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(resultReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(resultReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(resultReceiver)
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

                pendingBaseUrl = call.argument("baseUrl")
                pendingSessionToken = call.argument("sessionToken")
                pendingMainRole = call.argument("mainRole")
                pendingSecondaryRole = call.argument("secondaryRole")
                pendingAutofillRole = call.argument("autofillRole")

                startMediaProjectionRequest()
                result.success(true)
            } else if (call.method == "stopService") {
                val intent = Intent(this, CaptureService::class.java)
                stopService(intent)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
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
