import 'dart:convert';

/// Xray 配置构建器 — 桌面端与移动端共用
///
/// 从 Clash 订阅凭证字典构建完整的 Xray JSON 配置，
/// 支持全部协议: VMess / VLESS / Trojan / Shadowsocks
/// 支持全部传输: TCP / WS / gRPC / H2
/// 支持全部安全: TLS / Reality / None
///
/// 此类提取自 xray_service.dart 和 xray_service_mobile.dart 的重复代码，
/// 确保桌面端和移动端行为完全一致（特别是 Reality 支持）。
class XrayConfigBuilder {
  XrayConfigBuilder._();

  // ===== Outbound 构建 =====

  /// 从 Clash proxy 字典构建 Xray outbound 配置
  ///
  /// [clashProxy] 包含: name, type, server, port, uuid/password, tls,
  /// reality-opts, ws-opts, grpc-opts, flow, cipher, client-fingerprint 等
  static Map<String, dynamic> buildOutbound(Map<String, dynamic> clashProxy) {
    final String type = (clashProxy['type'] ?? 'vless').toString().toLowerCase();
    final String server = (clashProxy['server'] ?? '').toString();
    final int port = (clashProxy['port'] is int)
        ? clashProxy['port']
        : int.tryParse(clashProxy['port']?.toString() ?? '443') ?? 443;
    final String uuid = (clashProxy['uuid'] ?? clashProxy['password'] ?? '').toString();

    // 1. Protocol Settings
    final settings = _buildProtocolSettings(type, server, port, uuid, clashProxy);

    // 2. Stream Settings (传输 + 安全)
    final streamSettings = _buildStreamSettings(type, server, clashProxy);

    // 3. 确定 Xray protocol 字段
    final protocol = _resolveProtocol(type);

    return {
      "tag": "proxy",
      "protocol": protocol,
      "settings": settings,
      "streamSettings": streamSettings,
    };
  }

  /// 构建协议相关的 settings 段
  static Map<String, dynamic> _buildProtocolSettings(
    String type,
    String server,
    int port,
    String uuid,
    Map<String, dynamic> clashProxy,
  ) {
    switch (type) {
      case 'vmess':
        return {
          "vnext": [
            {
              "address": server,
              "port": port,
              "users": [
                {
                  "id": uuid,
                  "alterId": clashProxy['alterId'] ?? clashProxy['alter-id'] ?? 0,
                  "security": clashProxy['cipher'] ?? "auto",
                }
              ]
            }
          ]
        };

      case 'vless':
        return {
          "vnext": [
            {
              "address": server,
              "port": port,
              "users": [
                {
                  "id": uuid,
                  "encryption": "none",
                  "flow": (clashProxy['flow'] ?? '').toString(),
                }
              ]
            }
          ]
        };

      case 'trojan':
        return {
          "servers": [
            {
              "address": server,
              "port": port,
              "password": clashProxy['password']?.toString() ?? uuid,
            }
          ]
        };

      case 'ss':
      case 'shadowsocks':
        return {
          "servers": [
            {
              "address": server,
              "port": port,
              "method": clashProxy['cipher']?.toString() ?? "aes-256-gcm",
              "password": clashProxy['password']?.toString() ?? uuid,
            }
          ]
        };

      default:
        // 兜底 VMess
        return {
          "vnext": [
            {
              "address": server,
              "port": port,
              "users": [
                {"id": uuid, "alterId": 0, "security": "auto"}
              ]
            }
          ]
        };
    }
  }

  /// 构建 streamSettings（传输协议 + 安全层）
  static Map<String, dynamic> _buildStreamSettings(
    String type,
    String server,
    Map<String, dynamic> clashProxy,
  ) {
    final String network = (clashProxy['network'] ?? 'tcp').toString();
    final bool tls = clashProxy['tls'] == true || clashProxy['tls'] == 'true';

    // 检测 Reality 模式
    final realityOpts = clashProxy['reality-opts'];
    final bool isReality = realityOpts != null && realityOpts is Map && realityOpts.isNotEmpty;

    String security = 'none';
    if (isReality) {
      security = 'reality';
    } else if (tls) {
      security = 'tls';
    }

    final streamSettings = <String, dynamic>{
      "network": network,
      "security": security,
    };

    // TLS 设置
    if (security == 'tls') {
      streamSettings["tlsSettings"] = {
        "serverName": (clashProxy['sni'] ?? clashProxy['servername'] ?? server).toString(),
        "allowInsecure": clashProxy['skip-cert-verify'] == true,
      };
    }

    // Reality 设置
    if (security == 'reality') {
      final ro = realityOpts as Map;
      streamSettings["realitySettings"] = {
        "serverName": (clashProxy['sni'] ?? clashProxy['servername'] ?? server).toString(),
        "fingerprint": (clashProxy['client-fingerprint'] ?? 'chrome').toString(),
        "publicKey": (ro['public-key'] ?? '').toString(),
        "shortId": (ro['short-id'] ?? '').toString(),
        "spiderX": (ro['spider-x'] ?? '').toString(),
      };
    }

    // WS 传输
    if (network == 'ws') {
      final wsOpts = clashProxy['ws-opts'];
      String wsPath = '/';
      String wsHost = server;
      if (wsOpts != null && wsOpts is Map) {
        wsPath = (wsOpts['path'] ?? '/').toString();
        final headers = wsOpts['headers'];
        if (headers != null && headers is Map) {
          wsHost = (headers['Host'] ?? headers['host'] ?? server).toString();
        }
      }
      streamSettings["wsSettings"] = {
        "path": wsPath,
        "headers": {"Host": wsHost},
      };
    }

    // gRPC 传输
    if (network == 'grpc') {
      final grpcOpts = clashProxy['grpc-opts'];
      String serviceName = '';
      if (grpcOpts != null && grpcOpts is Map) {
        serviceName = (grpcOpts['grpc-service-name'] ?? '').toString();
      }
      streamSettings["grpcSettings"] = {
        "serviceName": serviceName,
        "multiMode": false,
      };
    }

    // H2 传输
    if (network == 'h2') {
      final h2Opts = clashProxy['h2-opts'];
      streamSettings["httpSettings"] = {
        "host": [server],
        "path": h2Opts?['path']?.toString() ?? '/',
      };
    }

    return streamSettings;
  }

  /// 解析 Clash type 到 Xray protocol
  static String _resolveProtocol(String type) {
    switch (type) {
      case 'trojan':
        return 'trojan';
      case 'vless':
        return 'vless';
      case 'ss':
      case 'shadowsocks':
        return 'shadowsocks';
      default:
        return 'vmess';
    }
  }

  // ===== Inbounds 构建 =====

  /// 通用 inbounds 生成（桌面端带 Stats API）
  static List<Map<String, dynamic>> buildDesktopInbounds(int httpPort, int socksPort, int statsPort) {
    return [
      {
        "tag": "http-in",
        "port": httpPort,
        "listen": "127.0.0.1",
        "protocol": "http",
        "settings": {},
      },
      {
        "tag": "socks-in",
        "port": socksPort,
        "listen": "127.0.0.1",
        "protocol": "socks",
        "settings": {"udp": true},
      },
      {
        "tag": "api",
        "port": statsPort,
        "listen": "127.0.0.1",
        "protocol": "dokodemo-door",
        "settings": {"address": "127.0.0.1"},
      },
    ];
  }

  /// 移动端 inbounds（无 Stats API dokodemo-door）
  static List<Map<String, dynamic>> buildMobileInbounds(int httpPort, int socksPort) {
    return [
      {
        "tag": "socks-in",
        "port": socksPort,
        "listen": "127.0.0.1",
        "protocol": "socks",
        "settings": {"udp": true},
      },
      {
        "tag": "http-in",
        "port": httpPort,
        "listen": "127.0.0.1",
        "protocol": "http",
        "settings": {},
      },
    ];
  }

  // ===== Stats / API / Policy 段 =====

  /// 通用 stats/api/policy 段（桌面端流量统计用）
  static Map<String, dynamic> buildStatsSection() {
    return {
      "stats": {},
      "api": {
        "tag": "api",
        "services": ["StatsService"],
      },
      "policy": {
        "system": {
          "statsInboundUplink": true,
          "statsInboundDownlink": true,
          "statsOutboundUplink": true,
          "statsOutboundDownlink": true,
        }
      },
    };
  }

  // ===== 完整配置生成 =====

  /// 生成桌面端完整 Xray 配置
  static Map<String, dynamic> generateDesktopConfig({
    required Map<String, dynamic> clashProxy,
    required String routingMode,
    required int httpPort,
    required int socksPort,
    required int statsPort,
  }) {
    if (routingMode == 'direct') {
      return _generateDirectConfig(
        inbounds: buildDesktopInbounds(httpPort, socksPort, statsPort),
        withStats: true,
      );
    }

    final outbound = buildOutbound(clashProxy);
    final inbounds = buildDesktopInbounds(httpPort, socksPort, statsPort);
    final server = (clashProxy['server'] ?? '').toString();

    // DNS 配置 — 通过代理解析，防止 DNS 泄漏和 ISP DNS 劫持
    final dnsServers = <Map<String, dynamic>>[
      // 远程 DNS，走代理出去（tag 对应 routing 中的规则）
      {"address": "8.8.8.8", "port": 53},
      {"address": "1.1.1.1", "port": 53},
    ];
    if (routingMode == 'rule') {
      // Rule 模式：中国域名走本地 DNS（加速）
      dnsServers.add({"address": "localhost", "domains": ["geosite:cn"]});
    }

    // 路由规则
    final routingRules = <Map<String, dynamic>>[
      // Stats API 路由（必须第一条）
      {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
    ];

    if (routingMode == 'rule') {
      // 中国域名直连
      routingRules.add({"type": "field", "domain": ["geosite:cn"], "outboundTag": "direct"});
      // 中国 IP + 私有 IP 直连
      routingRules.add({"type": "field", "ip": ["geoip:cn", "geoip:private"], "outboundTag": "direct"});
      // 广告屏蔽
      routingRules.add({"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block"});
    } else {
      // Global 模式：私有 IP 直连 + VPN 服务器 IP 直连（防止路由环路）
      final directIps = <String>["geoip:private"];
      // 将服务器 IP 加入直连规则，避免代理流量自身被代理
      if (server.isNotEmpty) {
        directIps.add(server);
      }
      routingRules.add({"type": "field", "ip": directIps, "outboundTag": "direct"});
    }

    return {
      "log": {"loglevel": "warning"},
      ...buildStatsSection(),
      "dns": {"servers": dnsServers},
      "inbounds": inbounds,
      "outbounds": [
        outbound,
        {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIP"}},
        {"tag": "block", "protocol": "blackhole"},
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": routingRules,
      },
    };
  }

  /// 生成移动端完整 Xray 配置
  static Map<String, dynamic> generateMobileConfig({
    required Map<String, dynamic> clashProxy,
    required String routingMode,
    required int httpPort,
    required int socksPort,
  }) {
    if (routingMode == 'direct') {
      return _generateDirectConfig(
        inbounds: buildMobileInbounds(httpPort, socksPort),
        withStats: false,
      );
    }

    final outbound = buildOutbound(clashProxy);
    final inbounds = buildMobileInbounds(httpPort, socksPort);

    // DNS 配置
    final dnsServers = <Map<String, dynamic>>[
      {"address": "8.8.8.8", "port": 53},
      {"address": "1.1.1.1", "port": 53},
    ];
    if (routingMode == 'rule') {
      dnsServers.add({"address": "localhost", "domains": ["geosite:cn"]});
    }

    // 路由规则
    final routingRules = <Map<String, dynamic>>[
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "direct"},
    ];
    if (routingMode == 'rule') {
      routingRules.add({"type": "field", "domain": ["geosite:cn"], "outboundTag": "direct"});
      routingRules.add({"type": "field", "ip": ["geoip:cn"], "outboundTag": "direct"});
    }

    return {
      "log": {"loglevel": "warning"},
      "dns": {"servers": dnsServers},
      "inbounds": inbounds,
      "outbounds": [
        outbound,
        {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIP"}},
        {"tag": "block", "protocol": "blackhole"},
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": routingRules,
      },
    };
  }

  /// 直连模式配置
  static Map<String, dynamic> _generateDirectConfig({
    required List<Map<String, dynamic>> inbounds,
    required bool withStats,
  }) {
    final config = <String, dynamic>{
      "log": {"loglevel": "warning"},
      "inbounds": inbounds,
      "outbounds": [
        {"tag": "direct", "protocol": "freedom"},
      ],
    };
    if (withStats) {
      config.addAll(buildStatsSection());
      config["routing"] = {
        "rules": [
          {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
        ]
      };
    }
    return config;
  }

  /// 将配置转为格式化 JSON 字符串
  static String toJsonString(Map<String, dynamic> config) {
    return const JsonEncoder.withIndent('  ').convert(config);
  }
}

