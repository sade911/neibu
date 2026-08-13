import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/vpn_provider.dart';
import '../../models/models.dart';
import '../../theme.dart';

class NodeListPage extends StatefulWidget {
  const NodeListPage({super.key});

  @override
  State<NodeListPage> createState() => _NodeListPageState();
}

class _NodeListPageState extends State<NodeListPage> {
  String _searchQuery = '';
  String _selectedFilter = '全部';
  bool _isPinging = false;

  @override
  void initState() {
    super.initState();
    _pingAll();
  }

  Future<void> _pingAll() async {
    setState(() => _isPinging = true);
    await context.read<VpnProvider>().pingAllNodes();
    if (mounted) setState(() => _isPinging = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('节点列表'),
        actions: [
          IconButton(
            icon: _isPinging
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.primary))
                : Icon(Icons.speed_rounded, color: AppTheme.primary),
            onPressed: _isPinging ? null : _pingAll,
            tooltip: '测速',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<VpnProvider>().fetchNodes(),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Consumer<VpnProvider>(
        builder: (_, vpn, __) {
          // Get unique regions
          final regions = <String>{'全部'};
          for (final n in vpn.nodes) {
            regions.add(n.regionTag);
          }

          // Filter nodes
          var filtered = vpn.nodes.where((n) {
            if (_selectedFilter != '全部' && n.regionTag != _selectedFilter) return false;
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              return n.name.toLowerCase().contains(q) || n.type.toLowerCase().contains(q);
            }
            return true;
          }).toList();

          return Column(
            children: [
              // Search
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: '搜索节点名称或协议...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              // Region Filters
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: regions.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(r, style: TextStyle(fontSize: 13)),
                      selected: _selectedFilter == r,
                      selectedColor: AppTheme.primary.withOpacity(0.2),
                      onSelected: (_) => setState(() => _selectedFilter = r),
                      side: BorderSide(
                        color: _selectedFilter == r ? AppTheme.primary : AppTheme.cardBorder,
                      ),
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 8),
              // Node List
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text('暂无节点', style: TextStyle(color: AppTheme.textSecondary)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _NodeTile(
                          node: filtered[i],
                          isSelected: vpn.selectedNode?.id == filtered[i].id,
                          onTap: () {
                            vpn.selectNode(filtered[i]);
                            Navigator.pop(context);
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  final NodeModel node;
  final bool isSelected;
  final VoidCallback onTap;

  const _NodeTile({
    required this.node,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary.withOpacity(0.08) : AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Region
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primary.withOpacity(0.15)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(
                  node.regionTag,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                )),
              ),
              const SizedBox(width: 12),
              // Name + Type
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.name,
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: isSelected ? AppTheme.primary : Colors.white,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(children: [
                    _ProtocolBadge(type: node.displayType),
                    const SizedBox(width: 6),
                    Text('${node.rate}x', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    ...node.tags.take(2).map((t) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(t, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    )),
                  ]),
                ],
              )),
              // Ping
              _PingBadge(pingMs: node.pingMs),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, color: AppTheme.primary, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProtocolBadge extends StatelessWidget {
  final String type;
  const _ProtocolBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(type, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary)),
    );
  }
}

class _PingBadge extends StatelessWidget {
  final int? pingMs;
  const _PingBadge({this.pingMs});

  @override
  Widget build(BuildContext context) {
    if (pingMs == null) {
      return SizedBox(
        width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.textSecondary),
      );
    }
    if (pingMs == -1) return const SizedBox.shrink();

    final color = pingMs! < 100
        ? AppTheme.success
        : pingMs! < 300
            ? AppTheme.warning
            : AppTheme.error;
    final text = pingMs! >= 999 ? '超时' : '${pingMs}ms';

    return Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color));
  }
}
