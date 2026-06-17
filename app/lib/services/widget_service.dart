import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../widgets/widget_design.dart';

class WidgetService {
  static const String _androidWidgetName = 'WeatherWidgetProvider';

  static Future<void> updateWidget(int widgetId, Device device, Measurement measurement, {
    List<String> metrics = const ['humidity'],
  }) async {
    try {
      final imagePath = await HomeWidget.renderFlutterWidget(
        WeatherWidgetDesign(
          device: device,
          measurement: measurement,
          selectedMetrics: metrics,
        ),
        key: 'widget_image_$widgetId',
        logicalSize: const Size(400, 200),
      );

      await HomeWidget.saveWidgetData('widget_image_$widgetId', imagePath);
      await HomeWidget.updateWidget(androidName: _androidWidgetName);
    } catch (_) {}
  }

  static Future<void> saveConfig(int widgetId, String deviceId, List<String> metrics) async {
    final prefs = await SharedPreferences.getInstance();
    final config = {
      'deviceId': deviceId,
      'metrics': metrics,
    };
    await prefs.setString('widget_config_$widgetId', jsonEncode(config));
  }

  static Future<List<int>> getActiveWidgetIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('active_widget_ids') ?? '';
    if (raw.isEmpty) return [];
    return raw.split(',').map((e) => int.tryParse(e)).whereType<int>().toList();
  }
}
