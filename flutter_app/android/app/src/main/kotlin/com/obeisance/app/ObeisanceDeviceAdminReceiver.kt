package com.obeisance.app

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

class ObeisanceDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        val prefs = context.getSharedPreferences(SAFETY_PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putLong(PENDING_SOS_TIMESTAMP_KEY, System.currentTimeMillis())
            .apply()

        context.sendBroadcast(Intent(ACTION_ADMIN_DISABLED_SOS).apply {
            setPackage(context.packageName)
            putExtra("event", "admin_disabled_sos")
        })
    }

    companion object {
        private const val SAFETY_PREFS = "obeisance_safety"
        private const val PENDING_SOS_TIMESTAMP_KEY = "pending_admin_disabled_sos"
        private const val ACTION_ADMIN_DISABLED_SOS = "com.obeisance.app.ACTION_ADMIN_DISABLED_SOS"
    }
}
