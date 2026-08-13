/// 用户模型
class UserModel {
  final int id;
  final String email;
  final int? planId;
  final int? expiredAt;
  final int transferEnable; // bytes
  final int transferUsed;   // d + u
  final String? token;

  UserModel({
    required this.id,
    required this.email,
    this.planId,
    this.expiredAt,
    required this.transferEnable,
    required this.transferUsed,
    this.token,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final d = json['d'] ?? 0;
    final u = json['u'] ?? 0;
    return UserModel(
      id: json['id'] ?? 0,
      email: json['email'] ?? '',
      planId: json['plan_id'],
      expiredAt: json['expired_at'],
      transferEnable: json['transfer_enable'] ?? 0,
      transferUsed: (d is int ? d : 0) + (u is int ? u : 0),
      token: json['token'],
    );
  }

  double get usedGB => transferUsed / (1024 * 1024 * 1024);
  double get totalGB => transferEnable / (1024 * 1024 * 1024);
  double get usagePercent => transferEnable > 0 ? transferUsed / transferEnable : 0;

  bool get isExpired {
    if (expiredAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 > expiredAt!;
  }

  String get expiredDateStr {
    if (expiredAt == null) return '永久';
    final dt = DateTime.fromMillisecondsSinceEpoch(expiredAt! * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

/// 节点模型
class NodeModel {
  final int id;
  final String name;
  final String type;
  String host;
  int port;
  final int serverPort;
  final double rate;
  final String flag;
  final List<String> tags;
  final Map<String, dynamic> rawConfig;
  final bool isOnline;
  int? pingMs;

  NodeModel({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.serverPort,
    required this.rate,
    required this.flag,
    required this.tags,
    required this.rawConfig,
    this.isOnline = false,
    this.pingMs,
  });

  factory NodeModel.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'] ?? 'Server';
    return NodeModel(
      id: json['id'] ?? 0,
      name: rawName.toString(),
      type: (json['type'] ?? 'vmess').toString(),
      host: json['host'] ?? '',
      port: _toInt(json['port'], 443),
      serverPort: _toInt(json['server_port'] ?? json['port'], 443),
      rate: (json['rate'] is num) ? (json['rate'] as num).toDouble() : 1.0,
      flag: _getFlagFromName(rawName.toString()),
      tags: _parseTags(json['tags']),
      rawConfig: json,
      isOnline: json['is_online'] == 1 || json['is_online'] == true,
    );
  }

  String get displayType => type.toUpperCase();
  String get regionTag => flag.isNotEmpty ? flag : 'UN';

  static int _toInt(dynamic v, int def) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? def;
  }

  static List<String> _parseTags(dynamic tags) {
    if (tags is List) return tags.map((t) => t.toString()).toList();
    return [];
  }

  static String _getFlagFromName(String name) {
    const flagMap = {
      '香港': 'HK', '日本': 'JP', '美国': 'US', '新加坡': 'SG',
      '台湾': 'TW', '韩国': 'KR', '英国': 'GB', '德国': 'DE',
      '法国': 'FR', '加拿大': 'CA', '澳大利亚': 'AU', '印度': 'IN',
      '印度尼西亚': 'ID', '俄罗斯': 'RU', '巴西': 'BR', '荷兰': 'NL',
      'Hong Kong': 'HK', 'Japan': 'JP', 'USA': 'US', 'Singapore': 'SG',
      'Taiwan': 'TW', 'Korea': 'KR',
    };
    for (final entry in flagMap.entries) {
      if (name.contains(entry.key)) return entry.value;
    }
    return 'UN';
  }
}

/// 套餐模型
class PlanModel {
  final int id;
  final String name;
  final int transferEnable;
  final double? monthPrice;

  PlanModel({
    required this.id,
    required this.name,
    required this.transferEnable,
    this.monthPrice,
  });

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    return PlanModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      transferEnable: json['transfer_enable'] ?? 0,
      monthPrice: json['month_price'] != null ? (json['month_price'] as num).toDouble() / 100 : null,
    );
  }
}
