package com.xattribution.xalarm.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import com.xattribution.xalarm.R
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Next alarm + the coming week of the shift rotation (filled = work day).
 */
class NextAlarmWidget : AppWidgetProvider() {

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
        val views = RemoteViews(context.packageName, R.layout.widget_next_alarm)
        views.setOnClickPendingIntent(R.id.root, WidgetStore.launchIntent(context, 0))

        val data = WidgetStore.data(context)
        val nextMs = data?.optLong("nextAlarmAtMs", -1L) ?: -1L
        if (nextMs > 0) {
            views.setTextViewText(R.id.tv_time, formatWhen(nextMs))
            val label = data?.optString("nextAlarmLabel").orEmpty()
            if (label.isEmpty()) {
                views.setViewVisibility(R.id.tv_label, View.GONE)
            } else {
                views.setViewVisibility(R.id.tv_label, View.VISIBLE)
                views.setTextViewText(R.id.tv_label, label)
            }
        } else {
            views.setTextViewText(R.id.tv_time, "No upcoming alarms")
            views.setViewVisibility(R.id.tv_label, View.GONE)
        }

        val cells = intArrayOf(
            R.id.c0, R.id.c1, R.id.c2, R.id.c3, R.id.c4, R.id.c5, R.id.c6,
        )
        val shiftDays = data?.optJSONArray("shiftDays")
        if (shiftDays == null || shiftDays.length() == 0) {
            views.setViewVisibility(R.id.strip, View.GONE)
        } else {
            views.setViewVisibility(R.id.strip, View.VISIBLE)
            for (i in cells.indices) {
                val day = shiftDays.optJSONObject(i) ?: continue
                val on = day.optBoolean("on")
                val today = day.optBoolean("today")
                views.setTextViewText(cells[i], day.optString("letter"))
                views.setInt(
                    cells[i],
                    "setBackgroundResource",
                    if (on) R.drawable.widget_cell_on else R.drawable.widget_cell_off,
                )
                views.setTextColor(
                    cells[i],
                    when {
                        today -> Color.parseColor("#CBAE86") // tan: today
                        on -> Color.parseColor("#F2F4F7")
                        else -> Color.parseColor("#9AA4B2")
                    },
                )
            }
        }
        return views
    }

    private fun formatWhen(ms: Long): String {
        val time = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(ms))
        val target = Calendar.getInstance().apply { timeInMillis = ms }
        val now = Calendar.getInstance()
        val dayDiff = target.get(Calendar.DAY_OF_YEAR) - now.get(Calendar.DAY_OF_YEAR) +
            (target.get(Calendar.YEAR) - now.get(Calendar.YEAR)) * 365
        return when {
            dayDiff == 0 -> "Today · $time"
            dayDiff == 1 -> "Tomorrow · $time"
            dayDiff in 2..6 ->
                SimpleDateFormat("EEE", Locale.getDefault()).format(Date(ms)) + " · $time"
            else ->
                SimpleDateFormat("MMM d", Locale.getDefault()).format(Date(ms)) + " · $time"
        }
    }
}
