package com.obeisance.app

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class SlumberActivity : AppCompatActivity() {
    private val dismissReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == SlumberModeManager.ACTION_DISMISS_OVERLAY) {
                if (isInLockTaskMode()) {
                    try {
                        stopLockTask()
                    } catch (_: IllegalStateException) {
                        // ignore
                    }
                }
                finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#0A0A0A"))
            gravity = Gravity.CENTER
            systemUiVisibility = (
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
        }

        val title = TextView(this).apply {
            text = "Slumber Mode Active"
            textSize = 28f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }

        val subtitle = TextView(this).apply {
            text = "Access is paused until your scheduled release window."
            textSize = 15f
            setTextColor(Color.parseColor("#D3B7FF"))
            gravity = Gravity.CENTER
            setPadding(48, 24, 48, 0)
        }

        container.addView(title)
        container.addView(subtitle)
        setContentView(container)

        registerReceiver(
            dismissReceiver,
            IntentFilter(SlumberModeManager.ACTION_DISMISS_OVERLAY)
        )

        tryStartLockTask()
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(dismissReceiver)
        } catch (_: IllegalArgumentException) {
            // Receiver not registered.
        }
        super.onDestroy()
    }

    override fun onBackPressed() {
        // Intentionally disabled.
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_VOLUME_UP,
            KeyEvent.KEYCODE_VOLUME_DOWN,
            KeyEvent.KEYCODE_HOME,
            KeyEvent.KEYCODE_APP_SWITCH -> true
            else -> super.onKeyDown(keyCode, event)
        }
    }

    private fun tryStartLockTask() {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(this, ObeisanceDeviceAdminReceiver::class.java)
        if (!dpm.isAdminActive(admin)) {
            return
        }

        try {
            dpm.setLockTaskPackages(admin, arrayOf(packageName))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && dpm.isLockTaskPermitted(packageName)) {
                startLockTask()
            }
        } catch (_: SecurityException) {
            // Best effort lock task only.
        }
    }

    private fun isInLockTaskMode(): Boolean {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            @Suppress("DEPRECATION")
            activityManager.isInLockTaskMode
        }
    }
}
