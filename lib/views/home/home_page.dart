import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/vpn_provider.dart';
import '../../theme.dart';
import 'node_list_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<VpnProvider>(
          builder: (_, vpn, __) {
            final isConnected = vpn.vpnState == VpnState.connected;
            final isConnecting = vpn.vpnState == VpnState.connecting;
            
            return Column(
              children: [
                // App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, color: AppTheme.primary, size: 28),
                      const SizedBox(width: 8),
                      Text('UUVPN PRO', style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700,
                        color: AppTheme.primary, letterSpacing: 1.5,
                      )),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded),
                        onPressed: () => vpn.logout(),
                        tooltip: '退出登录',
                      ),
                    ],
                  ),
                ),

                // User Info Card
                if (vpn.user != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _UserCard(user: vpn.user!),
                  ),

                const Spacer(),

                // Connect Button
                _ConnectButton(
                  state: vpn.vpnState,
                  onTap: () => vpn.toggleConnection(),
                ),

                const SizedBox(height: 16),

                // Status Text
                Text(
                  isConnected ? '已连接' : isConnecting ? '连接中...' : '未连接',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isConnected ? AppTheme.success : AppTheme.textSecondary,
                  ),
                ),

                // Traffic Stats
                if (isConnected) ...[
                  const SizedBox(height: 8),
                  Text(
                    '↑ ${_formatBytes(vpn.uploadBytes)}  ↓ ${_formatBytes(vpn.downloadBytes)}',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ],

                const Spacer(),

                // Selected Node / Node Select
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: InkWell(
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const NodeListPage())),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Row(
                        children: [
                          // Flag
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(child: Text(
                              vpn.selectedNode?.regionTag ?? '🌍',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            )),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vpn.selectedNode?.name ?? '点击选择节点',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                vpn.selectedNode != null
                                    ? '${vpn.selectedNode!.displayType} · ${vpn.selectedNode!.rate}x'
                                    : '请先选择一个节点',
                                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ],
                          )),
                          Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}

class _UserCard extends StatelessWidget {
  final dynamic user;
  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.card, AppTheme.card.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.email, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                '${user.usedGB.toStringAsFixed(1)} / ${user.totalGB.toStringAsFixed(0)} GB',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          )),
          Text(
            '到期: ${user.expiredDateStr}',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  final VpnState state;
  final VoidCallback onTap;
  const _ConnectButton({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isConnected = state == VpnState.connected;
    final isConnecting = state == VpnState.connecting;
    final size = 140.0;

    return GestureDetector(
      onTap: isConnecting ? null : onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: isConnected
                ? [AppTheme.primary.withOpacity(0.3), AppTheme.primary.withOpacity(0.05)]
                : [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.02)],
          ),
          border: Border.all(
            color: isConnected ? AppTheme.primary : Colors.white.withOpacity(0.2),
            width: 3,
          ),
          boxShadow: isConnected
              ? [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)]
              : [],
        ),
        child: Center(
          child: isConnecting
              ? SizedBox(
                  width: 36, height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppTheme.primary,
                  ),
                )
              : Icon(
                  Icons.power_settings_new_rounded,
                  size: 48,
                  color: isConnected ? AppTheme.primary : Colors.white.withOpacity(0.6),
                ),
        ),
      ),
    );
  }
}
