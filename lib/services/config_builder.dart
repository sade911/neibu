import 'dart:convert';
import '../models/models.dart';

/// 构建 sing-box JSON 配置
class SingBoxConfigBuilder {
  /// 从 NodeModel + UUID 构建完整 sing-box 配置
  static String build({
    required NodeModel node,
    required String uuid,
    int httpPort = 7890,
    int socksPort = 7891,
  }) {
    final outbound = _buildOutbound(node, uuid);
    
    final config = {
      'log': {'level': 'warn', 'timestamp': true},
      'dns': {
        'servers': [
          {'tag': 'remote-dns', 'address': 'https://8.8.8.8/dns-query', 'detour': 'proxy'},
          {'tag': 'local-dns', 'address': 'https://223.5.5.5/dns-query', 'detour': 'direct'},
          {'tag': 'block-dns', 'address': 'rcode://success'},
        ],
        'rules': [
          {'outbound': ['any'], 'server': 'local-dns'},
          {'clash_mode': 'Direct', 'server': 'local-dns'},
          {'clash_mode': 'Global', 'server': 'remote-dns'},
          {'rule_set': 'geosite-cn', 'server': 'local-dns'},
        ],
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'inet4_address': '172.19.0.1/30',
          'inet6_address': 'fdfe:dcba:9876::1/126',
          'auto_route': true,
          'strict_route': true,
          'stack': 'system',
          'sniff': true,
          'sniff_override_destination': true,
        },
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': httpPort,
        },
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
        {'type': 'dns', 'tag': 'dns-out'},
      ],
      'route': {
        'auto_detect_interface': true,
        'final': 'proxy',
        'rules': [
          {'protocol': 'dns', 'outbound': 'dns-out'},
          {'clash_mode': 'Direct', 'outbound': 'direct'},
          {'clash_mode': 'Global', 'outbound': 'proxy'},
          {'rule_set': 'geoip-cn', 'outbound': 'direct'},
          {'rule_set': 'geosite-cn', 'outbound': 'direct'},
          {'ip_is_private': true, 'outbound': 'direct'},
        ],
        'rule_set': [
          {
            'tag': 'geoip-cn',
            'type': 'remote',
            'format': 'binary',
            'url': 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
            'download_detour': 'proxy',
          },
          {
            'tag': 'geosite-cn',
            'type': 'remote',
            'format': 'binary',
            'url': 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs',
            'download_detour': 'proxy',
          },
        ],
      },
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:9090',
        },
        'cache_file': {
          'enabled': true,
        },
      },
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  static Map<String, dynamic> _buildOutbound(NodeModel node, String uuid) {
    final raw = node.rawConfig;
    final ps = raw['protocol_settings'] as Map<String, dynamic>? ?? {};

    switch (node.type.toLowerCase()) {
      case 'vless':
        return _buildVless(node, uuid, ps);
      case 'trojan':
        return _buildTrojan(node, uuid, ps);
      case 'vmess':
        return _buildVmess(node, uuid, ps);
      case 'hysteria':
      case 'hysteria2':
        return _buildHysteria2(node, uuid, ps);
      case 'shadowsocks':
        return _buildShadowsocks(node, uuid, ps);
      case 'tuic':
        return _buildTuic(node, uuid, ps);
      default:
        return {'type': 'direct', 'tag': 'proxy'};
    }
  }

  static Map<String, dynamic> _buildVless(NodeModel node, String uuid, Map<String, dynamic> ps) {
    final out = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': node.host,
      'server_port': node.serverPort,
      'uuid': uuid,
    };

    // Flow
    final flow = ps['flow']?.toString() ?? '';
    if (flow.isNotEmpty) out['flow'] = flow;

    // Network
    final network = ps['network']?.toString() ?? 'tcp';
    if (network == 'grpc') {
      final ns = ps['network_settings'] ?? {};
      out['transport'] = {
        'type': 'grpc',
        'service_name': ns['serviceName'] ?? ns['service_name'] ?? 'grpc',
      };
    } else if (network == 'ws') {
      final ns = ps['network_settings'] ?? {};
      out['transport'] = {
        'type': 'ws',
        'path': ns['path'] ?? '/ws',
      };
    }

    // TLS / Reality
    final rs = ps['reality_settings'] as Map<String, dynamic>? ?? {};
    if (rs.isNotEmpty) {
      out['tls'] = {
        'enabled': true,
        'server_name': rs['server_name'] ?? 'www.microsoft.com',
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
        'reality': {
          'enabled': true,
          'public_key': rs['public_key'] ?? '',
          'short_id': rs['short_id'] ?? '',
        },
      };
    } else {
      final tls = ps['tls'];
      if (tls != null && tls != 0) {
        out['tls'] = {'enabled': true, 'insecure': true};
      }
    }

    return out;
  }

  static Map<String, dynamic> _buildTrojan(NodeModel node, String uuid, Map<String, dynamic> ps) {
    final out = <String, dynamic>{
      'type': 'trojan',
      'tag': 'proxy',
      'server': node.host,
      'server_port': node.serverPort,
      'password': uuid,
    };

    final rs = ps['reality_settings'] as Map<String, dynamic>? ?? {};
    if (rs.isNotEmpty) {
      out['tls'] = {
        'enabled': true,
        'server_name': rs['server_name'] ?? 'www.microsoft.com',
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
        'reality': {
          'enabled': true,
          'public_key': rs['public_key'] ?? '',
          'short_id': rs['short_id'] ?? '',
        },
      };
    } else {
      out['tls'] = {'enabled': true, 'insecure': true};
    }

    return out;
  }

  static Map<String, dynamic> _buildVmess(NodeModel node, String uuid, Map<String, dynamic> ps) {
    final out = <String, dynamic>{
      'type': 'vmess',
      'tag': 'proxy',
      'server': node.host,
      'server_port': node.serverPort,
      'uuid': uuid,
      'alter_id': 0,
      'security': 'auto',
    };

    final network = ps['network']?.toString() ?? 'tcp';
    if (network == 'ws') {
      final ns = ps['network_settings'] ?? {};
      out['transport'] = {
        'type': 'ws',
        'path': ns['path'] ?? '/ws',
      };
    }

    final tls = ps['tls'];
    if (tls != null && tls != 0) {
      out['tls'] = {'enabled': true, 'insecure': true};
    }

    return out;
  }

  static Map<String, dynamic> _buildHysteria2(NodeModel node, String uuid, Map<String, dynamic> ps) {
    final out = <String, dynamic>{
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': node.host,
      'server_port': node.serverPort,
      'password': uuid,
      'tls': {
        'enabled': true,
        'insecure': true,
      },
    };

    final obfs = ps['obfs'] as Map<String, dynamic>? ?? {};
    if (obfs['open'] == true) {
      out['obfs'] = {
        'type': obfs['type'] ?? 'salamander',
        'password': obfs['password'] ?? '',
      };
    }

    return out;
  }

  static Map<String, dynamic> _buildShadowsocks(NodeModel node, String uuid, Map<String, dynamic> ps) {
    final cipher = ps['cipher'] ?? 'aes-256-gcm';
    // SS 2022 uses server_key from config, others use uuid
    final password = (cipher.toString().startsWith('2022'))
        ? (node.rawConfig['server_key'] ?? uuid)
        : uuid;

    return {
      'type': 'shadowsocks',
      'tag': 'proxy',
      'server': node.host,
      'server_port': node.serverPort,
      'method': cipher,
      'password': password,
    };
  }

  static Map<String, dynamic> _buildTuic(NodeModel node, String uuid, Map<String, dynamic> ps) {
    return {
      'type': 'tuic',
      'tag': 'proxy',
      'server': node.host,
      'server_port': node.serverPort,
      'uuid': uuid,
      'password': uuid,
      'congestion_control': ps['congestion_control'] ?? 'bbr',
      'udp_relay_mode': ps['udp_relay_mode'] ?? 'native',
      'tls': {
        'enabled': true,
        'insecure': true,
        'alpn': ['h3'],
      },
    };
  }
}
