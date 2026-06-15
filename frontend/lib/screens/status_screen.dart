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

  final _javaHist = <MetricsModel>[];
  final _bedrockHist = <MetricsModel>[];

  StreamSubscription<MetricsModel>? _javaSub;
  StreamSubscription<MetricsModel>? _bedrockSub;

  int _tab = 0; // 0 = Java, 1 = Bedrock
  String? _javaError;
  String? _bedrockError;
  DateTime? _javaLastUpdated;
  DateTime? _bedrockLastUpdated;

  static const _histMax = 20;

  @override
  void initState() {
    super.initState();
    _startStreams();
  }

  void _startStreams() {
    _javaSub?.cancel();
    _bedrockSub?.cancel();

    _javaSub = _service.streamMetrics(bedrock: false).listen(
      (m) {
        if (!mounted) return;
        setState(() {
          _javaHist.add(m);
          if (_javaHist.length > _histMax) _javaHist.removeAt(0);
          _javaError = null;
          _javaLastUpdated = DateTime.now();
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _javaError = e.toString());
      },
    );

    _bedrockSub = _service.streamMetrics(bedrock: true).listen(
      (m) {
        if (!mounted) return;
        setState(() {
          _bedrockHist.add(m);
          if (_bedrockHist.length > _histMax) _bedrockHist.removeAt(0);
          _bedrockError = null;
          _bedrockLastUpdated = DateTime.now();
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _bedrockError = e.toString());
      },
    );
  }

  @override
  void dispose() {
    _javaSub?.cancel();
    _bedrockSub?.cancel();
    super.dispose();
  }

  List<MetricsModel> get _currentHist => _tab == 0 ? _javaHist : _bedrockHist;
  MetricsModel? get _currentMetrics =>
      _currentHist.isEmpty ? null : _currentHist.last;
  bool get _loading => _currentMetrics == null;
  String? get _currentError => _tab == 0 ? _javaError : _bedrockError;
  DateTime? get _lastUpdated =>
      _tab == 0 ? _javaLastUpdated : _bedrockLastUpdated;

  List<double> _spark(double Function(MetricsModel) extract) =>
      _currentHist.map(extract).toList();

  String _formatTime(DateTime? dt) {
    if (dt == null) return '---';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Color _latencyColor(double ms) {
    if (ms <= 0) return AppTheme.accentCyan;
    if (ms < 50) return AppTheme.accentGreen;
    if (ms < 200) return AppTheme.accentAmber;
    return AppTheme.offlineColor;
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
    final m = _currentMetrics!;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    final isMobile = width < 480;

    return RefreshIndicator(
      onRefresh: () async => _startStreams(),
      color: AppTheme.accentCyan,
      backgroundColor: AppTheme.cardColor,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_currentError != null) _buildErrorBanner(),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              const SizedBox(width: 8),
              _RefreshButton(onPressed: _startStreams),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _TabButton(
                label: 'Java',
                selected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              const SizedBox(width: 6),
              _TabButton(
                label: 'Bedrock',
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
            ],
          ),
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
        Expanded(child: _latencyCard(m)),
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
            Expanded(child: _latencyCard(m)),
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
        _latencyCard(m),
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
        progressValue:
            m.players.max > 0 ? m.players.online / m.players.max : 0,
        sparkData: _spark((x) => x.players.online.toDouble()),
      );

  Widget _latencyCard(MetricsModel m) => MetricCard(
        label: 'LATENCY',
        value: m.latencyMs > 0 ? '${m.latencyMs.toStringAsFixed(0)} ms' : '---',
        icon: Icons.signal_cellular_alt,
        accentColor: _latencyColor(m.latencyMs),
        progressValue:
            m.latencyMs > 0 ? (m.latencyMs / 500).clamp(0.0, 1.0) : null,
        sparkData: _spark((x) => x.latencyMs),
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
        sparkData: _spark((x) => x.memory.usagePercent),
      );

  Widget _cpuCard(MetricsModel m) => MetricCard(
        label: 'CPU',
        value: m.cpuUsage > 0 ? '${m.cpuUsage.toStringAsFixed(1)}%' : '---',
        subValue: 'usage',
        icon: Icons.developer_board,
        accentColor: AppTheme.accentAmber,
        progressValue: m.cpuUsage > 0 ? m.cpuUsage / 100 : null,
        sparkData: _spark((x) => x.cpuUsage),
      );
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accentCyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppTheme.accentCyan : AppTheme.borderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.accentCyan : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
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
        tooltip: '再接続',
      ),
    );
  }
}
