import 'package:home_widget/home_widget.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class WidgetService {
  static const String _groupId = 'group.net.timm_sander.sws'; // Not used in Android but good practice
  static const String _androidWidgetName = 'WeatherWidgetProvider';

  static Future<void> updateWidget(Device device, Measurement measurement) async {
    try {
      await HomeWidget.saveWidgetData('widget_title', device.name);
      await HomeWidget.saveWidgetData('widget_temperature', '${measurement.temperature.toStringAsFixed(1)}°C');
      await HomeWidget.saveWidgetData('widget_description', measurement.zambretti);
      
      final time = DateFormat('HH:mm').format(DateTime.now());
      await HomeWidget.saveWidgetData('widget_update', 'Stand: $time Uhr');

      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
      );
    } catch (e) {
      // Widget-Update fehlgeschlagen
    }
  }
}
