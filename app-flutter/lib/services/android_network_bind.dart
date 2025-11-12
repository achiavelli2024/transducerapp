import 'package:flutter/services.dart';

class AndroidNetworkBind {
  static const MethodChannel _channel = MethodChannel('transducer/network');

  /// Bind process to an available Wi‑Fi network. Optionally pass ssid to filter.
  static Future<String?> bindToWifi({String? ssid}) async {
    try {
      final res = await _channel.invokeMethod('bindToWifi', {'ssid': ssid});
      return res as String?;
    } on PlatformException catch (e) {
      throw Exception('bindToWifi failed: ${e.message}');
    }
  }

  /// Unbind previously bound network
  static Future<String?> unbind() async {
    try {
      final res = await _channel.invokeMethod('unbindNetwork');
      return res as String?;
    } on PlatformException catch (e) {
      throw Exception('unbind failed: ${e.message}');
    }
  }
}