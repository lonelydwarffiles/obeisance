package com.obeisance.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import org.json.JSONObject

class ObeisanceAccessibilityService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            return
        }

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
        clearTargetFromRecents(activePackage)
    }

    override fun onInterrupt() {
        // No-op.
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

    private fun clearTargetFromRecents(targetPackage: String) {
        // Skeleton hook: perform best-effort cleanup after redirection.
        // Implement explicit task removal here if your device policy allows it.
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    companion object {
        private const val REDIRECT_PREFS = "obeisance_mdm"
        private const val REDIRECT_RULES_KEY = "redirect_rules"
    }
}
