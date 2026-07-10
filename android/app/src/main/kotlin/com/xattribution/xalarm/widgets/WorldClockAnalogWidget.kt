package com.xattribution.xalarm.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import com.xattribution.xalarm.R

/**
 * Analog style: two watch faces side by side for the first two world-clock
 * cities. Per-face time zones need Android 12+; on older versions both
 * faces show local time (the label still names the city).
 */
class WorldClockAnalogWidget : AppWidgetProvider() {

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
        val views = RemoteViews(context.packageName, R.layout.widget_world_clock_analog)
        views.setOnClickPendingIntent(R.id.root, WidgetStore.launchIntent(context, 1))

        val zones = WidgetStore.data(context)?.optJSONArray("zones")
        val cells = listOf(
            Triple(R.id.cell1, R.id.analog1, R.id.acity1),
            Triple(R.id.cell2, R.id.analog2, R.id.acity2),
        )
        for ((i, cell) in cells.withIndex()) {
            val zone = zones?.optJSONObject(i)
            if (zone == null) {
                views.setViewVisibility(cell.first, View.GONE)
            } else {
                views.setViewVisibility(cell.first, View.VISIBLE)
                views.setTextViewText(cell.third, zone.optString("city"))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    views.setString(cell.second, "setTimeZone", zone.optString("tz"))
                }
            }
        }
        return views
    }
}
