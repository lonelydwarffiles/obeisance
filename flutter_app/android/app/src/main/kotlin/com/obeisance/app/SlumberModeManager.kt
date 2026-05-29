package com.obeisance.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

object SlumberModeManager {
    private const val SLUMBER_PREFS = "obeisance_slumber"
    private const val KEY_START_TIME = "start_time"
    private const val KEY_END_TIME = "end_time"
    private const val KEY_PACKAGES = "non_essential_packages"

    const val ACTION_START = "com.obeisance.app.ACTION_SLUMBER_START"
    const val ACTION_END = "com.obeisance.app.ACTION_SLUMBER_END"
    const val ACTION_DISMISS_OVERLAY = "com.obeisance.app.ACTION_SLUMBER_DISMISS_OVERLAY"

    fun schedule(context: Context, startTime: String, endTime: String, packages: List<String>) {
        val prefs = context.getSharedPreferences(SLUMBER_PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_START_TIME, startTime)
            .putString(KEY_END_TIME, endTime)
            .putStringSet(KEY_PACKAGES, packages.toSet())
            .apply()

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        scheduleExact(alarmManager, context, ACTION_START, nextTriggerFor(startTime))
        scheduleExact(alarmManager, context, ACTION_END, nextEndTrigger(startTime, endTime))
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(alarmIntent(context, ACTION_START))
        alarmManager.cancel(alarmIntent(context, ACTION_END))
        val prefs = context.getSharedPreferences(SLUMBER_PREFS, Context.MODE_PRIVATE)
        prefs.edit().clear().apply()
    }

    fun handleStart(context: Context) {
        val packages = getPackages(context)
        setPackagesSuspended(context, packages, true)

        val launch = Intent(context, SlumberActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        context.startActivity(launch)

        val prefs = context.getSharedPreferences(SLUMBER_PREFS, Context.MODE_PRIVATE)
        val startTime = prefs.getString(KEY_START_TIME, null)
        if (!startTime.isNullOrBlank()) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            scheduleExact(alarmManager, context, ACTION_START, nextTriggerFor(startTime))
        }
    }

    fun handleEnd(context: Context) {
        val packages = getPackages(context)
        setPackagesSuspended(context, packages, false)

        context.sendBroadcast(Intent(ACTION_DISMISS_OVERLAY).apply {
            setPackage(context.packageName)
        })

        val prefs = context.getSharedPreferences(SLUMBER_PREFS, Context.MODE_PRIVATE)
        val startTime = prefs.getString(KEY_START_TIME, null)
        val endTime = prefs.getString(KEY_END_TIME, null)
        if (!startTime.isNullOrBlank() && !endTime.isNullOrBlank()) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            scheduleExact(alarmManager, context, ACTION_END, nextEndTrigger(startTime, endTime))
        }
    }

    private fun getPackages(context: Context): List<String> {
        val prefs = context.getSharedPreferences(SLUMBER_PREFS, Context.MODE_PRIVATE)
        return prefs.getStringSet(KEY_PACKAGES, emptySet())?.toList().orEmpty()
    }

    private fun setPackagesSuspended(context: Context, packages: List<String>, suspended: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || packages.isEmpty()) {
            return
        }

        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(context, ObeisanceDeviceAdminReceiver::class.java)
        if (!dpm.isAdminActive(admin)) {
            return
        }

        try {
            dpm.setPackagesSuspended(admin, packages.toTypedArray(), suspended)
        } catch (_: SecurityException) {
            // Best-effort only.
        } catch (_: IllegalArgumentException) {
            // Best-effort only.
        }
    }

    private fun scheduleExact(alarmManager: AlarmManager, context: Context, action: String, triggerAt: Long) {
        val intent = alarmIntent(context, action)
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, intent)
    }

    private fun alarmIntent(context: Context, action: String): PendingIntent {
        val intent = Intent(context, SlumberAlarmReceiver::class.java).apply {
            this.action = action
            setPackage(context.packageName)
        }
        val requestCode = if (action == ACTION_START) 9101 else 9102
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun nextTriggerFor(time24h: String): Long {
        val (hour, minute) = parseTime(time24h)
        val now = Calendar.getInstance()
        val target = Calendar.getInstance().apply {
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            if (before(now)) {
                add(Calendar.DATE, 1)
            }
        }
        return target.timeInMillis
    }

    private fun nextEndTrigger(startTime24h: String, endTime24h: String): Long {
        val (startHour, startMinute) = parseTime(startTime24h)
        val (endHour, endMinute) = parseTime(endTime24h)

        val now = Calendar.getInstance()
        val start = Calendar.getInstance().apply {
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            set(Calendar.HOUR_OF_DAY, startHour)
            set(Calendar.MINUTE, startMinute)
            if (before(now)) {
                add(Calendar.DATE, 1)
            }
        }

        val end = Calendar.getInstance().apply {
            timeInMillis = start.timeInMillis
            set(Calendar.HOUR_OF_DAY, endHour)
            set(Calendar.MINUTE, endMinute)
            if (before(start) || equals(start)) {
                add(Calendar.DATE, 1)
            }
        }

        return end.timeInMillis
    }

    private fun parseTime(value: String): Pair<Int, Int> {
        val parts = value.split(":")
        val hour = parts.getOrNull(0)?.toIntOrNull() ?: 0
        val minute = parts.getOrNull(1)?.toIntOrNull() ?: 0
        return hour.coerceIn(0, 23) to minute.coerceIn(0, 59)
    }
}
