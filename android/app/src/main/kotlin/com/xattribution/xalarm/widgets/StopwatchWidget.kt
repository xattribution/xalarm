package com.xattribution.xalarm.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import com.xattribution.xalarm.R
import java.util.Locale

/**
 * Live stopwatch. While running it uses a Chronometer, which ticks natively
 * without waking the app; paused/reset shows the frozen elapsed time.
 */
class StopwatchWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, render(context))
        }
    }

    private fun render(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_stopwatch)
        views.setOnClickPendingIntent(R.id.root, WidgetStore.launchIntent(context))

        val sw = WidgetStore.data(context)?.optJSONObject("stopwatch")
        val accumulatedMs = sw?.optLong("accumulatedMs", 0L) ?: 0L
        val runningSince = sw?.optLong("runningSinceEpochMs", -1L) ?: -1L

        if (runningSince > 0) {
            val elapsed =
                accumulatedMs + (System.currentTimeMillis() - runningSince)
            views.setViewVisibility(R.id.chrono, View.VISIBLE)
            views.setViewVisibility(R.id.tv_elapsed, View.GONE)
            views.setChronometer(
                R.id.chrono,
                SystemClock.elapsedRealtime() - elapsed,
                null,
                true,
            )
            views.setTextViewText(R.id.tv_state, "RUNNING")
        } else {
            views.setViewVisibility(R.id.chrono, View.GONE)
            views.setViewVisibility(R.id.tv_elapsed, View.VISIBLE)
            views.setTextViewText(R.id.tv_elapsed, format(accumulatedMs))
            views.setTextViewText(
                R.id.tv_state,
                if (accumulatedMs > 0) "PAUSED" else "STOPWATCH",
            )
        }
        return views
    }

    private fun format(ms: Long): String {
        val totalSeconds = ms / 1000
        val h = totalSeconds / 3600
        val m = (totalSeconds % 3600) / 60
        val s = totalSeconds % 60
        return if (h > 0) {
            String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        } else {
            String.format(Locale.US, "%02d:%02d", m, s)
        }
    }
}
