import 'package:flutter/material.dart';
import '../models/metrics_model.dart';
import '../theme/app_theme.dart';

class PlayerListCard extends StatelessWidget {
  final PlayersInfo players;
  // Pub/Sub 経由で /list コマンドをトリガーするコールバック（null なら非表示）
  final Future<void> Function()? onListRefresh;

  const PlayerListCard({
    super.key,
    required this.players,
    this.onListRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people, color: AppTheme.accentCyan, size: 18),
              const SizedBox(width: 8),
              Text(
                'ONLINE PLAYERS',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${players.online} / ${players.max}',
                  style: TextStyle(
                    color: AppTheme.accentCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onListRefresh != null) ...[
                const SizedBox(width: 4),
                _ListTriggerButton(onPressed: onListRefresh!),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (players.list.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  players.online == 0 ? 'No players online' : 'Player list unavailable',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: players.list
                  .map((name) => _PlayerChip(name: name))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

// Pub/Sub 経由で /list コマンドをトリガーするボタン（回転アニメ + 多重押下防止）
class _ListTriggerButton extends StatefulWidget {
  final Future<void> Function() onPressed;
  const _ListTriggerButton({required this.onPressed});

  @override
  State<_ListTriggerButton> createState() => _ListTriggerButtonState();
}

class _ListTriggerButtonState extends State<_ListTriggerButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handle() async {
    if (_loading) return;
    setState(() => _loading = true);
    _ctrl.repeat();
    await widget.onPressed();
    if (!mounted) return;
    _ctrl.stop();
    _ctrl.reset();
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: IconButton(
        onPressed: _loading ? null : _handle,
        icon: const Icon(Icons.refresh),
        color: AppTheme.accentGreen,
        iconSize: 18,
        constraints: const BoxConstraints(),
        padding: const EdgeInsets.all(4),
        visualDensity: VisualDensity.compact,
        tooltip: 'プレイヤーリスト更新（/list）',
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final String name;
  const _PlayerChip({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, color: AppTheme.onlineColor, size: 14),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
