package com.xattribution.xalarm.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.xattribution.xalarm.R

/**
 * Compares two world-clock cities side by side. Uses TextClock, which keeps
 * itself on time natively — no periodic refresh needed.
 */
class WorldClockWidget : AppWidgetProvider() {

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
        val views = RemoteViews(context.packageName, R.layout.widget_world_clock)
        views.setOnClickPendingIntent(R.id.root, WidgetStore.launchIntent(context))

        val zones = WidgetStore.data(context)?.optJSONArray("zones")
        val rows = listOf(
            Triple(R.id.row1, R.id.city1, R.id.clock1),
            Triple(R.id.row2, R.id.city2, R.id.clock2),
        )

        var shown = 0
        for ((i, row) in rows.withIndex()) {
            val zone = zones?.optJSONObject(i)
            if (zone == null) {
                views.setViewVisibility(row.first, View.GONE)
            } else {
                shown++
                views.setViewVisibility(row.first, View.VISIBLE)
                views.setTextViewText(row.second, zone.optString("city"))
                views.setString(row.third, "setTimeZone", zone.optString("tz"))
            }
        }
        views.setViewVisibility(
            R.id.tv_empty,
            if (shown == 0) View.VISIBLE else View.GONE,
        )
        return views
    }
}
