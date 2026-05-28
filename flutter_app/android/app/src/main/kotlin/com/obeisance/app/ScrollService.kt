package com.obeisance.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.TextView
import kotlin.math.abs
import org.json.JSONObject

class ScrollService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private var overlayView: View? = null
    private var cooldownActive = false

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> handleRedirect(event)
            AccessibilityEvent.TYPE_VIEW_SCROLLED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> handleScrollInterception(event)
        }
    }

    override fun onInterrupt() {
        removeCooldownOverlay()
    }

    override fun onDestroy() {
        removeCooldownOverlay()
        super.onDestroy()
    }

    private fun handleRedirect(event: AccessibilityEvent) {
        val activePackage = event.packageName?.toString() ?: return
        val redirectRules = getRedirectRules()
        val destinationPackage = redirectRules[activePackage] ?: return
        if (destinationPackage == activePackage) {
            return
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(destinationPackage)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
        } ?: return

        startActivity(launchIntent)
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    private fun handleScrollInterception(event: AccessibilityEvent) {
        if (cooldownActive) {
            return
        }

        val activePackage = event.packageName?.toString() ?: return
        if (!getRestrictedPackages().contains(activePackage)) {
            return
        }

        val scrollDistance = estimateScrollDistance(event)
        if (scrollDistance <= getScrollThreshold()) {
            return
        }

        cooldownActive = true
        performGlobalAction(GLOBAL_ACTION_BACK)
        showCooldownOverlay()
        handler.postDelayed({
            removeCooldownOverlay()
            cooldownActive = false
        }, COOLDOWN_DURATION_MS)
    }

    private fun estimateScrollDistance(event: AccessibilityEvent): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val delta = event.scrollDeltaY
            if (delta != 0) {
                return abs(delta)
            }
        }

        val itemSpan = if (event.fromIndex >= 0 && event.toIndex >= 0) {
            abs(event.toIndex - event.fromIndex)
        } else {
            0
        }
        if (itemSpan > 0) {
            return itemSpan * ITEM_SCROLL_UNIT
        }

        return if (event.maxScrollY > 0) {
            abs(event.scrollY)
        } else {
            0
        }
    }

    private fun showCooldownOverlay() {
        if (overlayView != null) {
            return
        }

        val windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val message = TextView(this).apply {
            text = "Cooldown"
            gravity = Gravity.CENTER
            textSize = 28f
            setTextColor(Color.WHITE)
            setBackgroundColor(0xCC000000.toInt())
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        )

        windowManager.addView(message, params)
        overlayView = message
    }

    private fun removeCooldownOverlay() {
        val windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        overlayView?.let {
            windowManager.removeView(it)
            overlayView = null
        }
    }

    private fun getRestrictedPackages(): Set<String> {
        val prefs = getSharedPreferences(REDIRECT_PREFS, Context.MODE_PRIVATE)
        return prefs.getStringSet(TEMPO_RESTRICTED_PACKAGES_KEY, DEFAULT_RESTRICTED_PACKAGES) ?: DEFAULT_RESTRICTED_PACKAGES
    }

    private fun getScrollThreshold(): Int {
        val prefs = getSharedPreferences(REDIRECT_PREFS, Context.MODE_PRIVATE)
        return when (prefs.getString(TEMPO_SENSITIVITY_KEY, DEFAULT_TEMPO_SENSITIVITY)) {
            TEMPO_SENSITIVITY_LOOSE -> LOOSE_SCROLL_THRESHOLD
            else -> STRICT_SCROLL_THRESHOLD
        }
    }

    private fun getRedirectRules(): Map<String, String> {
        val prefs = getSharedPreferences(REDIRECT_PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(REDIRECT_RULES_KEY, null) ?: return emptyMap()
        val json = JSONObject(raw)
        val rules = mutableMapOf<String, String>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            rules[key] = json.optString(key)
        }
        return rules
    }

    companion object {
        private const val REDIRECT_PREFS = "obeisance_mdm"
        private const val REDIRECT_RULES_KEY = "redirect_rules"
        private const val TEMPO_SENSITIVITY_KEY = "tempo_sensitivity"
        private const val TEMPO_RESTRICTED_PACKAGES_KEY = "tempo_restricted_packages"
        private const val DEFAULT_TEMPO_SENSITIVITY = "strict"
        private const val TEMPO_SENSITIVITY_LOOSE = "loose"
        private const val STRICT_SCROLL_THRESHOLD = 160
        private const val LOOSE_SCROLL_THRESHOLD = 520
        private const val ITEM_SCROLL_UNIT = 120
        private const val COOLDOWN_DURATION_MS = 2_000L
        private val DEFAULT_RESTRICTED_PACKAGES = setOf(
            "com.instagram.android",
            "com.google.android.youtube",
            "com.zhiliaoapp.musically",
            "com.twitter.android",
            "com.reddit.frontpage"
        )
    }
}
