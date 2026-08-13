import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Xboard API 客户端
class XboardApi {
  String? _baseUrl;
  String? _authToken;

  void configure({required String baseUrl, String? authToken}) {
    _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    _authToken = authToken;
  }

  bool get isConfigured => _baseUrl != null && _baseUrl!.isNotEmpty;
  bool get isAuthenticated => _authToken != null && _authToken!.isNotEmpty;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  // ============================================================
  // Auth
  // ============================================================

  /// 登录
  Future<Map<String, dynamic>> login(String email, String password) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/v1/passport/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(resp.body);
    if (resp.statusCode == 200 && data['data'] != null) {
      _authToken = data['data']['auth_data'] ?? data['data']['token'];
      return {'success': true, 'token': _authToken, 'data': data['data']};
    }
    return {'success': false, 'message': data['message'] ?? '登录失败'};
  }

  /// 注册
  Future<Map<String, dynamic>> register(String email, String password, {String? inviteCode}) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
    };
    if (inviteCode != null && inviteCode.isNotEmpty) {
      body['invite_code'] = inviteCode;
    }
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/v1/passport/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = jsonDecode(resp.body);
    if (resp.statusCode == 200 && data['data'] != null) {
      _authToken = data['data']['auth_data'] ?? data['data']['token'];
      return {'success': true, 'token': _authToken};
    }
    return {'success': false, 'message': data['message'] ?? '注册失败'};
  }

  // ============================================================
  // User
  // ============================================================

  /// 获取用户信息
  Future<UserModel?> getUserInfo() async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/api/v1/user/info'),
      headers: _headers,
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (data['data'] != null) {
        return UserModel.fromJson(data['data']);
      }
    }
    return null;
  }

  /// 获取订阅信息（含 subscribe_url）
  Future<Map<String, dynamic>?> getSubscribeInfo() async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/api/v1/user/getSubscribe'),
      headers: _headers,
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return data['data'];
    }
    return null;
  }

  // ============================================================
  // Servers
  // ============================================================

  /// 获取节点列表
  Future<List<NodeModel>> fetchNodes() async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/api/v1/user/server/fetch'),
      headers: _headers,
    );
    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body);
    final list = data['data'] as List? ?? [];
    return list.map((j) => NodeModel.fromJson(j)).toList();
  }

  /// 下载 Clash 订阅（获取凭证）
  Future<String?> downloadSubscription(String subscribeUrl) async {
    final url = subscribeUrl.contains('?')
        ? '$subscribeUrl&flag=clash'
        : '$subscribeUrl?flag=clash';
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) return resp.body;
    return null;
  }
}
