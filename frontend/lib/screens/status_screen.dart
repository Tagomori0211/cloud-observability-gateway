import 'dart:async';
import 'package:flutter/material.dart';
import '../models/metrics_model.dart';
import '../services/metrics_grpc_service.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/player_list_card.dart';
import '../widgets/server_status_card.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final _service = MetricsGrpcService();
  MetricsModel? _metrics;
  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;
  Timer? _timer;

  static const _refreshInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(_refreshInterval, (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() {
      _loading = _metrics == null;
      _error = null;
    });
    try {
      final m = await _service.fetchMetrics();
      if (!mounted) return;
      setState(() {
        _metrics = m;
        _loading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _metrics = _metrics ?? MetricsModel.offline();
        _loading = false;
        _error = e.toString();
        _lastUpdated = DateTime.now();
      });
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '---';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.accentCyan),
              )
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final m = _metrics!;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    final isMobile = width < 480;

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppTheme.accentCyan,
      backgroundColor: AppTheme.cardColor,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(m)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_error != null) _buildErrorBanner(),
                const SizedBox(height: 20),
                ServerStatusCard(metrics: m),
                const SizedBox(height: 20),
                isWide
                    ? _buildMetricsGridWide(m)
                    : isMobile
                        ? _buildMetricsGridMobile(m)
                        : _buildMetricsGridNarrow(m),
                const SizedBox(height: 20),
                PlayerListCard(players: m.players),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(MetricsModel m) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          Icon(Icons.dns, color: AppTheme.accentCyan, size: 22),
          const SizedBox(width: 10),
          Text(
            'TAGOMORI STATUS',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          Text(
            '更新: ${_formatTime(_lastUpdated)}',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 12),
          _RefreshButton(onPressed: _fetch),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.offlineColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.offlineColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: AppTheme.offlineColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'APIへの接続に失敗しました。前回のデータを表示しています。',
              style: TextStyle(color: AppTheme.offlineColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGridWide(MetricsModel m) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _playerCountCard(m)),
        const SizedBox(width: 16),
        Expanded(child: _tpsCard(m)),
        const SizedBox(width: 16),
        Expanded(child: _memoryCard(m)),
        const SizedBox(width: 16),
        Expanded(child: _cpuCard(m)),
      ],
    );
  }

  Widget _buildMetricsGridNarrow(MetricsModel m) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _playerCountCard(m)),
            const SizedBox(width: 16),
            Expanded(child: _tpsCard(m)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _memoryCard(m)),
            const SizedBox(width: 16),
            Expanded(child: _cpuCard(m)),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricsGridMobile(MetricsModel m) {
    return Column(
      children: [
        _playerCountCard(m),
        const SizedBox(height: 16),
        _tpsCard(m),
        const SizedBox(height: 16),
        _memoryCard(m),
        const SizedBox(height: 16),
        _cpuCard(m),
      ],
    );
  }

  Widget _playerCountCard(MetricsModel m) => MetricCard(
        label: 'PLAYERS',
        value: '${m.players.online}',
        subValue: '/ ${m.players.max} max',
        icon: Icons.people,
        accentColor: AppTheme.accentGreen,
        progressValue: m.players.max > 0
            ? m.players.online / m.players.max
            : 0,
      );

  Widget _tpsCard(MetricsModel m) => MetricCard(
        label: 'TPS',
        value: m.tps > 0 ? m.tps.toStringAsFixed(1) : '---',
        subValue: '/ 20.0 max',
        icon: Icons.speed,
        accentColor: AppTheme.tpsColor(m.tps),
        progressValue: m.tps > 0 ? (m.tps / 20.0).clamp(0.0, 1.0) : null,
      );

  Widget _memoryCard(MetricsModel m) => MetricCard(
        label: 'MEMORY',
        value: m.memory.maxMb > 0 ? '${m.memory.usedMb} MB' : '---',
        subValue: m.memory.maxMb > 0
            ? '/ ${m.memory.maxMb} MB (${(m.memory.usagePercent * 100).toStringAsFixed(0)}%)'
            : null,
        icon: Icons.memory,
        accentColor: AppTheme.accentPurple,
        progressValue: m.memory.maxMb > 0 ? m.memory.usagePercent : null,
      );

  Widget _cpuCard(MetricsModel m) => MetricCard(
        label: 'CPU',
        value: m.cpuUsage > 0 ? '${m.cpuUsage.toStringAsFixed(1)}%' : '---',
        subValue: 'usage',
        icon: Icons.developer_board,
        accentColor: AppTheme.accentAmber,
        progressValue: m.cpuUsage > 0 ? m.cpuUsage / 100 : null,
      );
}

class _RefreshButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _RefreshButton({required this.onPressed});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handlePress() {
    _ctrl.forward(from: 0);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: IconButton(
        onPressed: _handlePress,
        icon: const Icon(Icons.refresh),
        color: AppTheme.accentCyan,
        iconSize: 20,
        tooltip: '手動更新',
      ),
    );
  }
}
