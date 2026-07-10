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
        views.setOnClickPendingIntent(R.id.root, WidgetStore.launchIntent(context, 1))

        val zones = WidgetStore.data(context)?.optJSONArray("zones")
        val rows = listOf(
            Triple(R.id.row1, R.id.city1, R.id.clock1),
            Triple(R.id.row2, R.id.city2, R.id.clock2),
            Triple(R.id.row3, R.id.city3, R.id.clock3),
            Triple(R.id.row4, R.id.city4, R.id.clock4),
            Triple(R.id.row5, R.id.city5, R.id.clock5),
            Triple(R.id.row6, R.id.city6, R.id.clock6),
            Triple(R.id.row7, R.id.city7, R.id.clock7),
            Triple(R.id.row8, R.id.city8, R.id.clock8),
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
