import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'xray_config_builder.dart';

/// 移动平台 (Android/iOS) 的 Xray VPN 服务实现
/// 通过 MethodChannel 与原生 VpnPlugin 通信
class XrayServiceMobile {
  static const _methodChannel = MethodChannel('com.uuvpn/vpn');
  static const _eventChannel = EventChannel('com.uuvpn/vpn_state');

  final StreamController<String> _logController = StreamController<String>.broadcast();
  final StreamController<String> _stateController = StreamController<String>.broadcast();

  String _state = 'stopped'; // stopped, starting, running, error

  String get state => _state;
  Stream<String> get logStream => _logController.stream;
  Stream<String> get stateStream => _stateController.stream;

  XrayServiceMobile() {
    // Listen to state changes from native
    _eventChannel.receiveBroadcastStream().listen(
      (event) {
        final newState = event.toString();
        // Parse detailed error messages: "error:xray_died:exitCode:output"
        if (newState.startsWith('error:')) {
          _state = 'error';
          _stateController.add('error');
          final parts = newState.split(':');
          final reason = parts.length > 1 ? parts[1] : 'unknown';
          final exitCode = parts.length > 2 ? parts[2] : '?';
          final output = parts.length > 3 ? parts.sublist(3).join(':') : '';
          _logController.add('[VPN] ❌ 错误: $reason (exit=$exitCode)');
          if (output.isNotEmpty) {
            _logController.add('[Xray] $output');
          }
        } else {
          _state = newState;
          _stateController.add(newState);
          _logController.add('[VPN] State: $newState');
        }
      },
      onError: (error) {
        _logController.add('[VPN] EventChannel error: $error');
      },
    );
  }

  /// 请求 VPN 权限
  Future<bool> prepareVpn() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('prepareVpn');
      return result ?? false;
    } catch (e) {
      _logController.add('[VPN] prepareVpn error: $e');
      return false;
    }
  }

  /// 启动 VPN（通过 MethodChannel 传配置给原生 Service）
  Future<bool> start({
    required Map<String, dynamic> clashProxy,
    required String routingMode,
    required int socksPort,
    required int httpPort,
    required int statsPort,
  }) async {
    try {
      _state = 'starting';
      _stateController.add('starting');

      // 生成 Xray JSON 配置（与 Windows 版相同的逻辑）
      final config = _generateXrayConfig(
        clashProxy: clashProxy,
        routingMode: routingMode,
        socksPort: socksPort,
        httpPort: httpPort,
        statsPort: statsPort,
      );

      final configJson = const JsonEncoder.withIndent('  ').convert(config);
      _logController.add('[VPN] 生成配置完成，模式: $routingMode');

      final result = await _methodChannel.invokeMethod<bool>('startVpn', {
        'config': configJson,
        'socksPort': socksPort,
        'httpPort': httpPort,
      });

      if (result == true) {
        _logController.add('[VPN] 启动请求已发送');
        return true;
      } else {
        _logController.add('[VPN] 需要 VPN 权限，请在弹窗中允许');
        return false;
      }
    } catch (e) {
      _logController.add('[VPN] 启动失败: $e');
      _state = 'error';
      _stateController.add('error');
      return false;
    }
  }

  /// 停止 VPN
  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod('stopVpn');
      _state = 'stopped';
      _stateController.add('stopped');
      _logController.add('[VPN] 已停止');
    } catch (e) {
      _logController.add('[VPN] 停止失败: $e');
    }
  }

  /// 检查是否运行中
  Future<bool> isRunning() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 获取流量统计（通过 Android TrafficStats）
  Future<Map<String, dynamic>?> getTrafficStats() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('getTrafficStats');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}
    return null;
  }

  /// 生成 Xray JSON 配置（委托给共用 XrayConfigBuilder）
  /// 修复：移动端现在完整支持 Reality / H2 / 全部传输模式
  Map<String, dynamic> _generateXrayConfig({
    required Map<String, dynamic> clashProxy,
    required String routingMode,
    required int socksPort,
    required int httpPort,
    required int statsPort,
  }) {
    return XrayConfigBuilder.generateMobileConfig(
      clashProxy: clashProxy,
      routingMode: routingMode,
      httpPort: httpPort,
      socksPort: socksPort,
    );
  }
}
