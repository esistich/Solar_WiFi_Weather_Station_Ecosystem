package net.timm_sander.sws

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class WeatherWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.weather_widget).apply {
                val title = widgetData.getString("widget_title", "Wetterstation")
                val temp = widgetData.getString("widget_temperature", "--.-°C")
                val desc = widgetData.getString("widget_description", "Keine Daten")
                val update = widgetData.getString("widget_update", "")

                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_temperature, temp)
                setTextViewText(R.id.widget_description, desc)
                setTextViewText(R.id.widget_update, update)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
