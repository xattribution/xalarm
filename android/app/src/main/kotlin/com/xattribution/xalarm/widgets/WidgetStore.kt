package com.xattribution.xalarm.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import org.json.JSONObject

/**
 * Shared storage for the widget data snapshot pushed from the Flutter side
 * (see WidgetSyncService in Dart), plus helpers used by all widgets.
 */
object WidgetStore {
    private const val PREFS = "xalarm_widgets"
    private const val KEY = "data"

    fun data(context: Context): JSONObject? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null)
            ?.let { runCatching { JSONObject(it) }.getOrNull() }

    fun save(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, json)
            .apply()
        updateAll(context)
    }

    /** Ask the system to refresh every xalarm widget currently placed. */
    fun updateAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val providers = listOf(
            NextAlarmWidget::class.java,
            WorldClockWidget::class.java,
            WorldClockAnalogWidget::class.java,
            StopwatchWidget::class.java,
            StopwatchClassicWidget::class.java,
        )
        for (cls in providers) {
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isEmpty()) continue
            val intent = Intent(context, cls).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }

    /**
     * Tap-to-open intent that deep-links to a bottom tab
     * (0 alarm · 1 clock · 2 stopwatch · 3 timer). Unique request codes per
     * tab keep the PendingIntent extras from colliding across widgets.
     */
    fun launchIntent(context: Context, tab: Int): PendingIntent {
        val intent = Intent(
            context,
            com.xattribution.xalarm.MainActivity::class.java,
        ).apply {
            action = Intent.ACTION_MAIN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("xalarm_tab", tab)
        }
        return PendingIntent.getActivity(
            context,
            100 + tab,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
