import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/xboard_api.dart';
import '../services/singbox_service.dart';
import '../services/config_builder.dart';

enum VpnState { disconnected, connecting, connected, disconnecting }

class VpnProvider extends ChangeNotifier {
  final XboardApi _api = XboardApi();
  final SingBoxService _singbox = SingBoxService();

  // ===== State =====
  VpnState _vpnState = VpnState.disconnected;
  UserModel? _user;
  List<NodeModel> _nodes = [];
  NodeModel? _selectedNode;
  String? _authToken;
  String? _subscribeUrl;
  String? _currentUuid;
  String _panelUrl = '';
  int _uploadBytes = 0;
  int _downloadBytes = 0;
  Timer? _statsTimer;

  // ===== Getters =====
  VpnState get vpnState => _vpnState;
  UserModel? get user => _user;
  List<NodeModel> get nodes => _nodes;
  NodeModel? get selectedNode => _selectedNode;
  bool get isLoggedIn => _authToken != null && _authToken!.isNotEmpty;
  String get panelUrl => _panelUrl;
  int get uploadBytes => _uploadBytes;
  int get downloadBytes => _downloadBytes;

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

    // 监听 VPN 状态变化
    _singbox.setStatusCallback((status) {
      if (status == 'running') {
        _vpnState = VpnState.connected;
        _startStatsTimer();
      } else {
        _vpnState = VpnState.disconnected;
        _stopStatsTimer();
      }
      notifyListeners();
    });

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

      // 保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('panel_url', _panelUrl);
      await prefs.setString('auth_token', _authToken!);
      await prefs.setString('login_email', email);

      // 获取订阅
      await _fetchSubscribeInfo();
      await refreshUserInfo();
      await fetchNodes();

      notifyListeners();
      return null; // success
    }
    return result['message']?.toString() ?? '登录失败';
  }

  Future<void> logout() async {
    _authToken = null;
    _user = null;
    _nodes = [];
    _selectedNode = null;
    _subscribeUrl = null;
    _currentUuid = null;

    if (_vpnState == VpnState.connected) {
      await disconnect();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('subscribe_url');
    await prefs.remove('current_uuid');

    notifyListeners();
  }

  // ============================================================
  // User / Nodes
  // ============================================================

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
      if (_subscribeUrl != null) {
        await prefs.setString('subscribe_url', _subscribeUrl!);
      }

      // 从订阅解析 UUID
      await _extractUuid();
    }
  }

  Future<void> _extractUuid() async {
    if (_subscribeUrl == null) return;
    final content = await _api.downloadSubscription(_subscribeUrl!);
    if (content == null) return;

    // 从 Clash YAML 中提取 UUID/password
    final uuidMatch = RegExp(r'uuid:\s*([a-f0-9\-]{36})', caseSensitive: false).firstMatch(content);
    if (uuidMatch != null) {
      _currentUuid = uuidMatch.group(1);
    } else {
      final pwdMatch = RegExp(r'password:\s*([a-f0-9\-]{36})', caseSensitive: false).firstMatch(content);
      if (pwdMatch != null) {
        _currentUuid = pwdMatch.group(1);
      }
    }

    if (_currentUuid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_uuid', _currentUuid!);
    }
  }

  // ============================================================
  // Node Selection
  // ============================================================

  void selectNode(NodeModel node) {
    _selectedNode = node;
    notifyListeners();
  }

  // ============================================================
  // VPN Connect / Disconnect
  // ============================================================

  Future<void> connect() async {
    if (_selectedNode == null || _currentUuid == null) return;
    if (_vpnState == VpnState.connecting || _vpnState == VpnState.connected) return;

    _vpnState = VpnState.connecting;
    notifyListeners();

    try {
      final configJson = SingBoxConfigBuilder.build(
        node: _selectedNode!,
        uuid: _currentUuid!,
      );

      final ok = await _singbox.start(configJson);
      if (ok) {
        _vpnState = VpnState.connected;
        _startStatsTimer();
      } else {
        _vpnState = VpnState.disconnected;
      }
    } catch (e) {
      _vpnState = VpnState.disconnected;
    }

    notifyListeners();
  }

  Future<void> disconnect() async {
    if (_vpnState == VpnState.disconnected) return;

    _vpnState = VpnState.disconnecting;
    notifyListeners();

    await _singbox.stop();
    _vpnState = VpnState.disconnected;
    _stopStatsTimer();
    _uploadBytes = 0;
    _downloadBytes = 0;

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
      if (node.host.isEmpty) {
        node.pingMs = -1;
        continue;
      }
      if (_udpProtocols.contains(node.type.toLowerCase())) {
        node.pingMs = node.isOnline ? 1 : 999;
        notifyListeners();
        continue;
      }
      try {
        final sw = Stopwatch()..start();
        final socket = await Socket.connect(node.host, node.port,
            timeout: const Duration(seconds: 3));
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
  // Stats Timer
  // ============================================================

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final stats = await _singbox.getTrafficStats();
      _uploadBytes = stats['upload'] ?? 0;
      _downloadBytes = stats['download'] ?? 0;
      notifyListeners();
    });
  }

  void _stopStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }
}
