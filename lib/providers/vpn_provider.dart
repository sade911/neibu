import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/xboard_api.dart';
import '../services/xray/xray_config_builder.dart';

enum VpnState { disconnected, connecting, connected, disconnecting }

class VpnProvider extends ChangeNotifier {
  final XboardApi _api = XboardApi();

  VpnState _vpnState = VpnState.disconnected;
  UserModel? _user;
  List<NodeModel> _nodes = [];
  NodeModel? _selectedNode;
  String? _authToken;
  String? _subscribeUrl;
  String? _currentUuid;
  String _panelUrl = '';
  Process? _xrayProcess;
  int _httpPort = 7890;
  int _socksPort = 7891;
  double _uploadSpeedKb = 0;
  double _downloadSpeedKb = 0;
  Timer? _statsTimer;

  VpnState get vpnState => _vpnState;
  UserModel? get user => _user;
  List<NodeModel> get nodes => _nodes;
  NodeModel? get selectedNode => _selectedNode;
  bool get isLoggedIn => _authToken != null && _authToken!.isNotEmpty;
  String get panelUrl => _panelUrl;
  double get uploadSpeedKb => _uploadSpeedKb;
  double get downloadSpeedKb => _downloadSpeedKb;

  VpnProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _panelUrl = prefs.getString('panel_url') ?? '';
    _authToken = prefs.getString('auth_token');
    _subscribeUrl = prefs.getString('subscribe_url');
    _currentUuid = prefs.getString('current_uuid');

    if (_panelUrl.isNotEmpty) {
      _api.configure(baseUrl: _panelUrl, authToken: _authToken);
    }

    if (isLoggedIn) {
      await refreshUserInfo();
      await fetchNodes();
    }
    notifyListeners();
  }

  // ============================================================
  // Auth
  // ============================================================

  Future<String?> login(String panelUrl, String email, String password) async {
    _panelUrl = panelUrl.replaceAll(RegExp(r'/+$'), '');
    _api.configure(baseUrl: _panelUrl);

    final result = await _api.login(email, password);
    if (result['success'] == true) {
      _authToken = result['token'];
      _api.configure(baseUrl: _panelUrl, authToken: _authToken);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('panel_url', _panelUrl);
      await prefs.setString('auth_token', _authToken!);
      await prefs.setString('login_email', email);

      await _fetchSubscribeInfo();
      await refreshUserInfo();
      await fetchNodes();
      notifyListeners();
      return null;
    }
    return result['message']?.toString() ?? '登录失败';
  }

  Future<void> logout() async {
    _authToken = null;
    _user = null;
    _nodes = [];
    _selectedNode = null;
    if (_vpnState == VpnState.connected) await disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('subscribe_url');
    await prefs.remove('current_uuid');
    notifyListeners();
  }

  Future<void> refreshUserInfo() async {
    _user = await _api.getUserInfo();
    notifyListeners();
  }

  Future<void> fetchNodes() async {
    _nodes = await _api.fetchNodes();
    notifyListeners();
  }

  Future<void> _fetchSubscribeInfo() async {
    final info = await _api.getSubscribeInfo();
    if (info != null) {
      _subscribeUrl = info['subscribe_url']?.toString();
      final prefs = await SharedPreferences.getInstance();
      if (_subscribeUrl != null) await prefs.setString('subscribe_url', _subscribeUrl!);
      await _extractUuid();
    }
  }

  Future<void> _extractUuid() async {
    if (_subscribeUrl == null) return;
    final content = await _api.downloadSubscription(_subscribeUrl!);
    if (content == null) return;
    final m = RegExp(r'uuid:\s*([a-f0-9\-]{36})', caseSensitive: false).firstMatch(content);
    if (m != null) {
      _currentUuid = m.group(1);
    } else {
      final p = RegExp(r'password:\s*([a-f0-9\-]{36})', caseSensitive: false).firstMatch(content);
      if (p != null) _currentUuid = p.group(1);
    }
    if (_currentUuid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_uuid', _currentUuid!);
    }
  }

  void selectNode(NodeModel node) {
    _selectedNode = node;
    notifyListeners();
  }

  // ============================================================
  // Connect / Disconnect (Xray + System Proxy)
  // ============================================================

  Future<void> connect() async {
    if (_selectedNode == null || _currentUuid == null) return;
    if (_vpnState != VpnState.disconnected) return;

    _vpnState = VpnState.connecting;
    notifyListeners();

    try {
      // Build Xray config
      final config = XrayConfigBuilder.buildConfig(
        node: _selectedNode!,
        uuid: _currentUuid!,
        httpPort: _httpPort,
        socksPort: _socksPort,
      );

      // Write config
      final appDir = await getApplicationSupportDirectory();
      final configFile = File('${appDir.path}/xray_config.json');
      await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(config));

      // Find xray.exe
      final exePath = _getXrayPath();
      if (!File(exePath).existsSync()) {
        _vpnState = VpnState.disconnected;
        notifyListeners();
        return;
      }

      // Start Xray
      _xrayProcess = await Process.start(exePath, ['-config', configFile.path]);
      await Future.delayed(const Duration(milliseconds: 500));

      // Set system proxy
      await _setSystemProxy(_httpPort);

      _vpnState = VpnState.connected;
      notifyListeners();
    } catch (e) {
      _vpnState = VpnState.disconnected;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _vpnState = VpnState.disconnecting;
    notifyListeners();

    await _clearSystemProxy();
    _xrayProcess?.kill();
    _xrayProcess = null;

    _vpnState = VpnState.disconnected;
    _uploadSpeedKb = 0;
    _downloadSpeedKb = 0;
    notifyListeners();
  }

  Future<void> toggleConnection() async {
    if (_vpnState == VpnState.connected) {
      await disconnect();
    } else if (_vpnState == VpnState.disconnected) {
      await connect();
    }
  }

  // ============================================================
  // Ping
  // ============================================================

  static const _udpProtocols = {'hysteria', 'hysteria2', 'tuic'};

  Future<void> pingAllNodes() async {
    for (final node in _nodes) {
      if (node.host.isEmpty) { node.pingMs = -1; continue; }
      if (_udpProtocols.contains(node.type.toLowerCase())) {
        node.pingMs = node.isOnline ? 1 : 999;
        notifyListeners();
        continue;
      }
      try {
        final sw = Stopwatch()..start();
        final socket = await Socket.connect(node.host, node.port, timeout: const Duration(seconds: 3));
        sw.stop();
        socket.destroy();
        node.pingMs = sw.elapsedMilliseconds;
      } catch (_) {
        node.pingMs = 999;
      }
      notifyListeners();
    }
  }

  // ============================================================
  // System Proxy (Windows)
  // ============================================================

  Future<void> _setSystemProxy(int port) async {
    await Process.run('reg', [
      'add', r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f',
    ]);
    await Process.run('reg', [
      'add', r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', '127.0.0.1:$port', '/f',
    ]);
  }

  Future<void> _clearSystemProxy() async {
    await Process.run('reg', [
      'add', r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f',
    ]);
  }

  String _getXrayPath() {
    final exe = Platform.resolvedExecutable;
    final dir = File(exe).parent.path;
    return '$dir/resources/xray/xray.exe';
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _xrayProcess?.kill();
    _clearSystemProxy();
    super.dispose();
  }
}
