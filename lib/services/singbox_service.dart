import 'package:flutter/services.dart';

/// sing-box 服务（通过 MethodChannel 与 Kotlin 桥接层通信）
class SingBoxService {
  static const _channel = MethodChannel('com.uuvpn/singbox');

  /// 启动 VPN
  Future<bool> start(String configJson) async {
    try {
      final result = await _channel.invokeMethod('start', {'config': configJson});
      return result == true;
    } on PlatformException catch (e) {
      print('SingBox start error: ${e.message}');
      return false;
    }
  }

  /// 停止 VPN
  Future<bool> stop() async {
    try {
      final result = await _channel.invokeMethod('stop');
      return result == true;
    } on PlatformException catch (e) {
      print('SingBox stop error: ${e.message}');
      return false;
    }
  }

  /// 获取运行状态
  Future<String> getStatus() async {
    try {
      final result = await _channel.invokeMethod('getStatus');
      return result?.toString() ?? 'stopped';
    } on PlatformException {
      return 'stopped';
    }
  }

  /// 获取流量统计
  Future<Map<String, int>> getTrafficStats() async {
    try {
      final result = await _channel.invokeMethod('getTrafficStats');
      if (result is Map) {
        return {
          'upload': (result['upload'] as num?)?.toInt() ?? 0,
          'download': (result['download'] as num?)?.toInt() ?? 0,
        };
      }
    } on PlatformException {
      // ignore
    }
    return {'upload': 0, 'download': 0};
  }

  /// 检查 VPN 权限
  Future<bool> requestVpnPermission() async {
    try {
      final result = await _channel.invokeMethod('requestVpnPermission');
      return result == true;
    } on PlatformException {
      return false;
    }
  }

  /// 设置状态变化回调
  void setStatusCallback(Function(String) callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onStatusChanged') {
        callback(call.arguments.toString());
      }
    });
  }
}
