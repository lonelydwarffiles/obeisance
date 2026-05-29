package com.obeisance.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SlumberAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            SlumberModeManager.ACTION_START -> SlumberModeManager.handleStart(context)
            SlumberModeManager.ACTION_END -> SlumberModeManager.handleEnd(context)
        }
    }
}
