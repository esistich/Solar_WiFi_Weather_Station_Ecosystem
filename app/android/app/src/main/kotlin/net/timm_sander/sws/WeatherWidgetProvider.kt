package net.timm_sander.sws

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class WeatherWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        // Wir nutzen den Standard-Flutter-Speicher für die IDs
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val currentIds = flutterPrefs.getString("flutter.active_widget_ids", "")
            ?.split(",")
            ?.filter { it.isNotEmpty() }
            ?.toMutableSet() ?: mutableSetOf()
            
        appWidgetIds.forEach { currentIds.add(it.toString()) }
        flutterPrefs.edit().putString("flutter.active_widget_ids", currentIds.joinToString(",")).apply()

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.weather_widget).apply {
                // home_widget nutzt standardmäßig seinen eigenen Store für die Pfade
                val imagePath = widgetData.getString("widget_image_$widgetId", null) 
                    ?: widgetData.getString("widget_image_default", null)
                
                if (imagePath != null) {
                    val file = File(imagePath)
                    if (file.exists()) {
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                        setImageViewBitmap(R.id.widget_image, bitmap)
                    }
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    override fun onDeleted(context: Context, widgetIds: IntArray) {
        super.onDeleted(context, widgetIds)
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val currentIds = flutterPrefs.getString("flutter.active_widget_ids", "")
            ?.split(",")
            ?.filter { it.isNotEmpty() }
            ?.toMutableSet() ?: mutableSetOf()
            
        widgetIds.forEach { currentIds.remove(it.toString()) }
        flutterPrefs.edit().putString("flutter.active_widget_ids", currentIds.joinToString(",")).apply()
    }
}
