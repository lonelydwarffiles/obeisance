package com.obeisance.app

import android.app.AppOpsManager
import android.app.WallpaperManager
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.net.VpnService
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.URL
import java.util.Calendar
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private lateinit var mdmChannel: MethodChannel
    private var textToSpeech: TextToSpeech? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        textToSpeech = TextToSpeech(this, this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mdmChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.obeisance/mdm")
        mdmChannel.setMethodCallHandler { call, result ->
            handleMdmCall(call, result)
        }
    }

    private fun handleMdmCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "lockScreen" -> {
                lockScreen(result)
            }

            "speakText" -> {
                val message = call.argument<String>("message")
                if (message.isNullOrBlank()) {
                    result.error("invalid_args", "message is required", null)
                    return
                }
                speakText(message)
                result.success(null)
            }

            "setWallpaper" -> {
                val imageUrl = call.argument<String>("imageUrl")
                if (imageUrl.isNullOrBlank()) {
                    result.error("invalid_args", "imageUrl is required", null)
                    return
                }
                setWallpaper(imageUrl, result)
            }

            "forceOpenUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("invalid_args", "url is required", null)
                    return
                }
                forceOpenUrl(url)
                result.success(null)
            }

            "updateRedirectRules" -> {
                val rules = call.argument<Map<String, String>>("rules").orEmpty()
                updateRedirectRules(rules)
                result.success(null)
            }

            "gatherAppInventory" -> {
                result.success(gatherAppInventory())
            }

            "gatherUsageStats" -> {
                result.success(gatherUsageStats())
            }

            "getScreentimeStats" -> {
                getScreentimeStats(result)
            }

            "startDnsFilter" -> {
                startDnsFilter(result)
            }

            "stopDnsFilter" -> {
                stopDnsFilter(result)
            }

            "setPackagesSuspended" -> {
                val packages = call.argument<List<String>>("packages").orEmpty()
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                val suspended = call.argument<Boolean>("suspended") ?: true
                setPackagesSuspended(packages, suspended, result)
            }

            "pauseMedia" -> {
                dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PAUSE)
                result.success(null)
            }

            "skipMedia" -> {
                dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_NEXT)
                result.success(null)
            }

            "getNowPlaying" -> {
                result.success(getNowPlaying())
            }

            else -> result.notImplemented()
        }
    }

    private fun lockScreen(result: MethodChannel.Result) {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        try {
            dpm.lockNow()
            result.success(null)
        } catch (error: SecurityException) {
            result.error("lock_failed", "Device admin permission is required to lock now", error.message)
        }
    }

    private fun speakText(message: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            textToSpeech?.speak(message, TextToSpeech.QUEUE_FLUSH, null, "obeisance-mdm")
        } else {
            @Suppress("DEPRECATION")
            textToSpeech?.speak(message, TextToSpeech.QUEUE_FLUSH, null)
        }
    }

    private fun setWallpaper(imageUrl: String, result: MethodChannel.Result) {
        try {
            URL(imageUrl).openStream().use { input ->
                WallpaperManager.getInstance(this).setStream(input)
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("wallpaper_failed", "Unable to set wallpaper", error.message)
        }
    }

    private fun forceOpenUrl(url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun updateRedirectRules(rules: Map<String, String>) {
        val prefs = getSharedPreferences(REDIRECT_PREFS, Context.MODE_PRIVATE)
        prefs.edit().putString(REDIRECT_RULES_KEY, JSONObject(rules).toString()).apply()
    }

    private fun gatherAppInventory(): List<String> {
        val applications = packageManager.getInstalledApplications(0)
        return applications.map { it.packageName }.sorted()
    }

    private fun gatherUsageStats(): Map<String, Long> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime = System.currentTimeMillis()
        val startTime = endTime - USAGE_WINDOW_MS
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )

        val aggregate = mutableMapOf<String, Long>()
        for (entry in stats) {
            val current = aggregate[entry.packageName] ?: 0L
            aggregate[entry.packageName] = current + entry.totalTimeInForeground
        }
        return aggregate
    }

    private fun getScreentimeStats(result: MethodChannel.Result) {
        if (!hasUsageStatsPermission()) {
            result.error(
                "usage_access_required",
                "Usage access is not granted. Launch Settings.ACTION_USAGE_ACCESS_SETTINGS to grant access.",
                Settings.ACTION_USAGE_ACCESS_SETTINGS
            )
            return
        }

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val midnight = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            midnight,
            now
        )
        val aggregate = mutableMapOf<String, Long>()
        for (entry in stats) {
            if (entry.packageName.isNullOrBlank() || entry.totalTimeInForeground <= 0L) {
                continue
            }
            val current = aggregate[entry.packageName] ?: 0L
            aggregate[entry.packageName] = current + entry.totalTimeInForeground
        }
        result.success(aggregate)
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOpsManager = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOpsManager.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOpsManager.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }

        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun startDnsFilter(result: MethodChannel.Result) {
        if (VpnService.prepare(this) != null) {
            result.error(
                "vpn_permission_required",
                "VPN consent is required. Launch VpnService.prepare() intent before starting DNS filter.",
                null
            )
            return
        }

        val serviceIntent = Intent(this, ObeisanceVpnService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        result.success(null)
    }

    private fun stopDnsFilter(result: MethodChannel.Result) {
        val stopped = stopService(Intent(this, ObeisanceVpnService::class.java))
        result.success(stopped)
    }

    private fun setPackagesSuspended(
        packages: List<String>,
        suspended: Boolean,
        result: MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error("unsupported", "Package suspension requires Android 9 (API 28)+", null)
            return
        }
        if (packages.isEmpty()) {
            result.success(emptyList<String>())
            return
        }

        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = dpm.activeAdmins?.firstOrNull { it.packageName == packageName }
        if (admin == null) {
            result.error(
                "admin_required",
                "No active device admin receiver found for package suspension.",
                null
            )
            return
        }

        try {
            val unaffected = dpm.setPackagesSuspended(admin, packages.toTypedArray(), suspended)
            result.success(unaffected?.toList() ?: emptyList<String>())
        } catch (error: SecurityException) {
            result.error("suspend_failed", "Device owner/admin privileges are required.", error.message)
        } catch (error: IllegalArgumentException) {
            result.error("suspend_failed", "Failed to suspend one or more packages.", error.message)
        }
    }

    private fun dispatchMediaKey(keyCode: Int) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val downEvent = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
        val upEvent = KeyEvent(KeyEvent.ACTION_UP, keyCode)
        audioManager.dispatchMediaKeyEvent(downEvent)
        audioManager.dispatchMediaKeyEvent(upEvent)
    }

    private fun getNowPlaying(): Map<String, String?> {
        val mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        val sessionControllers: List<MediaController> = try {
            val listener = ComponentName(this, NotificationListenerStub::class.java)
            mediaSessionManager.getActiveSessions(listener)
        } catch (_: SecurityException) {
            emptyList()
        }

        val controller = sessionControllers.firstOrNull { it.metadata != null } ?: return mapOf(
            "track" to null,
            "artist" to null
        )
        val metadata = controller.metadata
        return mapOf(
            "track" to metadata?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE),
            "artist" to metadata?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST)
        )
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            textToSpeech?.language = Locale.getDefault()
        }
    }

    override fun onDestroy() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }

    companion object {
        private const val REDIRECT_PREFS = "obeisance_mdm"
        private const val REDIRECT_RULES_KEY = "redirect_rules"
        private const val USAGE_WINDOW_MS = 24 * 60 * 60 * 1000L
    }
}

private class NotificationListenerStub
