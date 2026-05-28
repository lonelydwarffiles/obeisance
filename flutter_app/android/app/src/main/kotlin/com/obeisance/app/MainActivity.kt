package com.obeisance.app

import android.app.WallpaperManager
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.URL
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
