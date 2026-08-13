import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'xray_config_builder.dart';


enum XrayState { stopped, starting, running, stopping, error }

class XrayService {
  Process? _process;
  XrayState _state = XrayState.stopped;
  final StreamController<String> _logController = StreamController<String>.broadcast();
  final StreamController<XrayState> _stateController = StreamController<XrayState>.broadcast();

  int _statsPort = 0;
  int _lastUplink = 0;
  int _lastDownlink = 0;

  XrayState get state => _state;
  Stream<String> get logStream => _logController.stream;
  Stream<XrayState> get stateStream => _stateController.stream;
  int get statsPort => _statsPort;

  /// 获取应用所在目录（安装后 exe 的所在目录）
  String getAppDir() {
    return path.dirname(Platform.resolvedExecutable);
  }

  /// 找到 xray.exe 路径
  String getExecutablePath() {
    final appDir = getAppDir();
    // 部署模式：<exe目录>/resources/xray/xray.exe
    final xrayBin = path.join(appDir, 'resources', 'xray', 'xray.exe');
    if (File(xrayBin).existsSync()) {
      return xrayBin;
    }
    // 开发模式：项目根/windows/resources/xray/xray.exe
    final devBin = path.join(Directory.current.path, 'windows', 'resources', 'xray', 'xray.exe');
    if (File(devBin).existsSync()) {
      return devBin;
    }
    return 'xray.exe';
  }

  void _updateState(XrayState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  void setStartingState() {
    _updateState(XrayState.starting);
  }

  // ===== 配置生成 — 委托给共用 XrayConfigBuilder =====

  /// Rule 模式：中国域名/IP 直连，广告屏蔽，其余走代理
  Map<String, dynamic> generateXrayConfig(Map<String, dynamic> clashProxy, int httpPort, int socksPort, int statsPort) {
    return XrayConfigBuilder.generateDesktopConfig(
      clashProxy: clashProxy,
      routingMode: 'rule',
      httpPort: httpPort,
      socksPort: socksPort,
      statsPort: statsPort,
    );
  }

  /// Global 模式：仅私有 IP 直连，其余全走代理
  Map<String, dynamic> generateXrayConfigGlobal(Map<String, dynamic> clashProxy, int httpPort, int socksPort, int statsPort) {
    return XrayConfigBuilder.generateDesktopConfig(
      clashProxy: clashProxy,
      routingMode: 'global',
      httpPort: httpPort,
      socksPort: socksPort,
      statsPort: statsPort,
    );
  }

  /// Direct 模式：全部直连
  Map<String, dynamic> generateXrayConfigDirect(int httpPort, int socksPort, int statsPort) {
    return XrayConfigBuilder.generateDesktopConfig(
      clashProxy: {},
      routingMode: 'direct',
      httpPort: httpPort,
      socksPort: socksPort,
      statsPort: statsPort,
    );
  }

  /// 查询 Xray 真实流量统计（返回每秒上传/下载 KB）
  Future<Map<String, double>> queryTrafficStats() async {
    if (_state != XrayState.running || _statsPort == 0) {
      return {'up': 0.0, 'down': 0.0};
    }
    try {
      final xrayExe = getExecutablePath();
      // 使用 xray api 命令查询 stats
      final result = await Process.run(xrayExe, [
        'api', 'statsquery', '--server=127.0.0.1:$_statsPort', '-pattern', ''
      ]);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        int totalUp = 0;
        int totalDown = 0;
        // 解析 JSON 输出
        try {
          final data = jsonDecode(output);
          if (data['stat'] != null) {
            for (final stat in data['stat']) {
              final name = stat['name']?.toString() ?? '';
              final value = (stat['value'] is int) ? stat['value'] as int : int.tryParse(stat['value']?.toString() ?? '0') ?? 0;
              if (name.contains('uplink')) totalUp += value;
              if (name.contains('downlink')) totalDown += value;
            }
          }
        } catch (_) {
          // 非 JSON 格式，按行解析
          for (final line in output.split('\n')) {
            if (line.contains('uplink')) {
              final match = RegExp(r'value:\s*(\d+)').firstMatch(line);
              if (match != null) totalUp += int.parse(match.group(1)!);
            }
            if (line.contains('downlink')) {
              final match = RegExp(r'value:\s*(\d+)').firstMatch(line);
              if (match != null) totalDown += int.parse(match.group(1)!);
            }
          }
        }
        // 计算差值（每秒增量）
        final upDelta = totalUp - _lastUplink;
        final downDelta = totalDown - _lastDownlink;
        _lastUplink = totalUp;
        _lastDownlink = totalDown;
        // 转换为 KB/s
        return {
          'up': upDelta > 0 ? upDelta / 1024.0 : 0.0,
          'down': downDelta > 0 ? downDelta / 1024.0 : 0.0,
        };
      }
    } catch (_) {}
    return {'up': 0.0, 'down': 0.0};
  }

  // ===== UUID 提取 =====
  // 参考 UUVPN-Windows electron/main.ts extractUuidFromSubscription

  /// 从订阅内容中提取 UUID
  String? extractUuidFromContent(String content) {
    // 1. YAML 格式: uuid: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    final uuidYaml = RegExp(r'uuid:\s*([a-f0-9-]{36})', caseSensitive: false).firstMatch(content);
    if (uuidYaml != null) return uuidYaml.group(1);

    // 2. VLESS 链接: vless://UUID@host:port
    final vlessMatch = RegExp(r'vless://([a-f0-9-]{36})@', caseSensitive: false).firstMatch(content);
    if (vlessMatch != null) return vlessMatch.group(1);

    // 3. VMess Base64 链接: vmess://base64...
    final vmessMatch = RegExp(r'vmess://([A-Za-z0-9+/=]+)', caseSensitive: false).firstMatch(content);
    if (vmessMatch != null) {
      try {
        final decoded = utf8.decode(base64.decode(vmessMatch.group(1)!));
        final parsed = jsonDecode(decoded) as Map<String, dynamic>;
        if (parsed.containsKey('id')) return parsed['id'] as String;
      } catch (_) {}
    }

    return null;
  }

  // ===== 配置文件准备 =====

  /// 生成 Xray 配置文件并返回路径
  Future<String> prepareConfigFile({
    required Map<String, dynamic> clashProxy,
    required String routingMode,
    required int httpPort,
    required int socksPort,
    required int statsPort,
  }) async {
    _statsPort = statsPort;
    _lastUplink = 0;
    _lastDownlink = 0;

    final configDir = Directory(path.join(getAppDir(), 'config'));
    if (!configDir.existsSync()) {
      configDir.createSync(recursive: true);
    }
    final configFile = File(path.join(configDir.path, 'xray_config.json'));

    Map<String, dynamic> config;
    if (routingMode == 'global') {
      config = generateXrayConfigGlobal(clashProxy, httpPort, socksPort, statsPort);
    } else if (routingMode == 'direct') {
      config = generateXrayConfigDirect(httpPort, socksPort, statsPort);
    } else {
      config = generateXrayConfig(clashProxy, httpPort, socksPort, statsPort);
    }

    await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(config));
    _logController.add('[Xray] 配置文件已生成 (模式: $routingMode, stats端口: $statsPort)');
    return configFile.path;
  }

  // ===== 系统代理管理 =====

  /// 开启 Windows 系统代理
  Future<void> enableSystemProxy(String host, int port) async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f'
      ]);
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyServer', '/t', 'REG_SZ',
        '/d', '$host:$port', '/f'
      ]);
      // 完整的内网 bypass 列表（防止内网访问异常）
      final bypass = '<local>;localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*';
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyOverride', '/t', 'REG_SZ',
        '/d', bypass, '/f'
      ]);
      await _refreshWinInetProxySettings();
      _logController.add('[System Proxy] 已设置系统代理 ($host:$port)');
    } catch (e) {
      _logController.add('[System Proxy Warning] 设置代理失败: $e');
    }
  }

  /// 关闭 Windows 系统代理
  Future<void> disableSystemProxy() async {
    if (!Platform.isWindows) return;
    try {
      // 1. 禁用代理开关
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f'
      ]);
      // 2. 清除 ProxyServer 残留值（防止浏览器读取到旧代理地址）
      await Process.run('reg', [
        'delete',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyServer', '/f'
      ]);
      // 3. 重置 WinHTTP 代理（部分应用依赖 WinHTTP 而非 WinINet）
      await Process.run('netsh', ['winhttp', 'reset', 'proxy']);
      // 4. 刷新 DNS 缓存（清除代理期间通过远端 DNS 解析的缓存）
      await Process.run('ipconfig', ['/flushdns']);
      // 5. 通知 WinINet 立即刷新代理设置
      await _refreshWinInetProxySettings();
      _logController.add('[System Proxy] 已释放系统代理');
    } catch (e) {
      _logController.add('[System Proxy Warning] 清理代理失败: $e');
    }
  }

  /// 刷新 WinINet 代理缓存
  Future<void> _refreshWinInetProxySettings() async {
    try {
      await Process.run('powershell', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
        r'''
$code = @"
using System;
using System.Runtime.InteropServices;
public class WinInet {
    [DllImport("wininet.dll")]
    public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);
    public static void Refresh() {
        InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);
        InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);
    }
}
"@; Add-Type -TypeDefinition $code; [WinInet]::Refresh()
'''
      ]);
    } catch (_) {}
  }

  // ===== TUN 模式（全局流量捕获）=====

  Process? _tunProcess;
  bool _tunModeActive = false;
  String? _originalGateway;
  String? _originalInterface;

  /// 获取 tun2socks 可执行文件路径
  String getTun2socksPath() {
    final appDir = getAppDir();
    // 部署模式
    final tunBin = path.join(appDir, 'resources', 'tun2socks', 'tun2socks.exe');
    if (File(tunBin).existsSync()) return tunBin;
    // 开发模式
    final devBin = path.join(Directory.current.path, 'windows', 'resources', 'tun2socks', 'tun2socks.exe');
    if (File(devBin).existsSync()) return devBin;
    return '';
  }

  /// 检查 TUN 模式是否可用（tun2socks 二进制存在）
  bool isTunModeAvailable() {
    return Platform.isWindows && getTun2socksPath().isNotEmpty;
  }

  /// 获取当前系统默认网关和接口名
  Future<void> _detectOriginalGateway() async {
    if (!Platform.isWindows) return;
    try {
      final result = await Process.run('powershell', [
        '-NoProfile', '-Command',
        r"Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1 | ForEach-Object { $_.NextHop + '|' + (Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex).InterfaceAlias }"
      ]);
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        final parts = output.split('|');
        if (parts.length >= 2) {
          _originalGateway = parts[0].trim();
          _originalInterface = parts[1].trim();
          _logController.add('[TUN] 检测到默认网关: $_originalGateway (接口: $_originalInterface)');
        }
      }
    } catch (e) {
      _logController.add('[TUN] 获取默认网关失败: $e');
    }
  }

  /// 启用 TUN 模式 — 使用 tun2socks 捕获全部系统流量
  /// serverAddress: VPN 远程服务器 IP，需排除路由防止环路
  Future<bool> enableTunMode(int socksPort, String serverAddress) async {
    if (!Platform.isWindows) return false;

    final tunExe = getTun2socksPath();
    if (tunExe.isEmpty) {
      _logController.add('[TUN] tun2socks 不存在，回退到 HTTP 代理模式');
      return false;
    }

    try {
      _logController.add('[TUN] 启动 TUN 模式 (全局流量捕获)...');

      // 1. 检测原始网关
      await _detectOriginalGateway();

      // 2. 启动 tun2socks
      _tunProcess = await Process.start(tunExe, [
        '-device', 'tun://uuvpn',
        '-proxy', 'socks5://127.0.0.1:$socksPort',
      ], workingDirectory: path.dirname(tunExe));

      _logController.add('[TUN] tun2socks 已启动 PID: ${_tunProcess!.pid}');

      // 等待 TUN 接口创建
      await Future.delayed(const Duration(seconds: 3));

      // 3. 配置 TUN 接口 IP
      await Process.run('netsh', [
        'interface', 'ip', 'set', 'address',
        'uuvpn', 'static', '10.0.0.2', '255.255.255.0', '10.0.0.1'
      ]);

      // 4. 设置 DNS
      await Process.run('netsh', [
        'interface', 'ip', 'set', 'dns', 'uuvpn', 'static', '8.8.8.8'
      ]);
      await Process.run('netsh', [
        'interface', 'ip', 'add', 'dns', 'uuvpn', '1.1.1.1', 'index=2'
      ]);

      // 5. 排除 VPN 服务器 IP（走原始网关，防止路由环路）
      if (serverAddress.isNotEmpty && _originalGateway != null) {
        await Process.run('route', [
          'add', serverAddress, 'mask', '255.255.255.255', _originalGateway!
        ]);
        _logController.add('[TUN] 排除服务器路由: $serverAddress → $_originalGateway');
      }

      // 6. 添加默认路由通过 TUN（低 metric 优先）
      await Process.run('route', [
        'add', '0.0.0.0', 'mask', '128.0.0.0', '10.0.0.1', 'metric', '5'
      ]);
      await Process.run('route', [
        'add', '128.0.0.0', 'mask', '128.0.0.0', '10.0.0.1', 'metric', '5'
      ]);

      // 7. 刷新 DNS
      await Process.run('ipconfig', ['/flushdns']);

      _tunModeActive = true;
      _logController.add('[TUN] ✅ TUN 模式已启用，所有流量走 VPN');

      // 监听 tun2socks 退出
      _tunProcess!.exitCode.then((code) {
        if (_tunModeActive) {
          _logController.add('[TUN] tun2socks 异常退出 (code: $code)');
          disableTunMode();
        }
      });

      return true;
    } catch (e) {
      _logController.add('[TUN] 启用 TUN 模式失败: $e');
      await disableTunMode();
      return false;
    }
  }

  /// 关闭 TUN 模式，恢复路由
  Future<void> disableTunMode() async {
    if (!Platform.isWindows) return;
    _tunModeActive = false;

    try {
      // 1. 删除 TUN 路由
      await Process.run('route', ['delete', '0.0.0.0', 'mask', '128.0.0.0', '10.0.0.1']);
      await Process.run('route', ['delete', '128.0.0.0', 'mask', '128.0.0.0', '10.0.0.1']);

      // 2. 停止 tun2socks
      if (_tunProcess != null) {
        try {
          _tunProcess!.kill(ProcessSignal.sigterm);
          await Future.delayed(const Duration(milliseconds: 500));
          _tunProcess?.kill(ProcessSignal.sigkill);
        } catch (_) {}
        _tunProcess = null;
      }

      // 3. 刷新 DNS
      await Process.run('ipconfig', ['/flushdns']);

      _logController.add('[TUN] TUN 模式已关闭');
    } catch (e) {
      _logController.add('[TUN] 关闭 TUN 模式时出错: $e');
    }
  }

  // ===== 进程管理 =====

  // 会话 ID：每次 start() 递增，防止旧进程的异步回调干扰新连接
  int _sessionId = 0;

  /// 启动 Xray 核心
  /// 优先使用 TUN 模式（全局流量捕获），不可用时 fallback 到 HTTP 系统代理
  Future<bool> start(String configFilePath, int httpPort, {int socksPort = 0, String serverAddress = ''}) async {
    if (_state == XrayState.running) return true;

    // 先确保旧进程完全停止
    await _killProcess();

    _sessionId++;
    final currentSession = _sessionId;

    _updateState(XrayState.starting);
    final exePath = getExecutablePath();

    if (!File(exePath).existsSync()) {
      _logController.add('[ERROR] Xray 核心不存在: $exePath');
      _updateState(XrayState.error);
      return false;
    }

    try {
      _logController.add('[Xray] 启动内核: $exePath');
      _logController.add('[Xray] 配置文件: $configFilePath');

      _process = await Process.start(
        exePath,
        ['run', '-config', configFilePath],
        workingDirectory: path.dirname(exePath),
      );

      _logController.add('[Xray] 内核已启动 PID: ${_process!.pid}');

      // 等待 2 秒确认进程存活
      await Future.delayed(const Duration(seconds: 2));
      if (_process == null || (await _process!.exitCode.timeout(const Duration(milliseconds: 100), onTimeout: () => -1)) != -1) {
        _logController.add('[ERROR] Xray 启动后立即退出');
        _updateState(XrayState.error);
        return false;
      }

      _updateState(XrayState.running);

      // 设置系统 HTTP 代理（可靠模式，覆盖浏览器和大部分应用）
      // 注: TUN 模式需要管理员权限 + WinTUN 驱动，默认不启用
      _logController.add('[Proxy] 设置系统 HTTP 代理 127.0.0.1:$httpPort');
      await enableSystemProxy('127.0.0.1', httpPort);

      // 监听日志
      _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.trim().isNotEmpty) {
          _logController.add('[Xray] ${line.trim()}');
        }
      });

      _process!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.trim().isNotEmpty) {
          _logController.add('[Xray WARN] ${line.trim()}');
        }
      });

      // 监听进程退出（仅当 session 未过期时才处理，防止竞态）
      _process!.exitCode.then((code) async {
        if (_sessionId != currentSession) return; // 已被新会话取代，忽略
        _logController.add('[Xray] 进程异常退出 (code: $code)');
        await disableTunMode();
        await disableSystemProxy();
        _updateState(XrayState.stopped);
        _process = null;
      });

      return true;
    } catch (e) {
      _logController.add('[ERROR] 启动 Xray 失败: $e');
      _updateState(XrayState.error);
      return false;
    }
  }

  /// 强制杀死当前进程（不触发代理清理）
  Future<void> _killProcess() async {
    if (_process != null) {
      try {
        _process!.kill(ProcessSignal.sigterm);
        await Future.delayed(const Duration(milliseconds: 300));
        _process?.kill(ProcessSignal.sigkill);
      } catch (_) {}
      _process = null;
    }
  }

  /// 停止 Xray 核心
  Future<void> stop() async {
    _sessionId++; // 使旧 exitCode 回调失效
    await disableTunMode();
    await disableSystemProxy();
    if (_process != null) {
      _updateState(XrayState.stopping);
      _logController.add('[Xray] 正在停止内核...');
      _process!.kill(ProcessSignal.sigterm);
      await Future.delayed(const Duration(milliseconds: 500));
      if (_process != null) {
        try { _process!.kill(ProcessSignal.sigkill); } catch (_) {}
      }
      _process = null;
      _updateState(XrayState.stopped);
      _logController.add('[Xray] 已断开，内核已停止');
    }
  }
}

