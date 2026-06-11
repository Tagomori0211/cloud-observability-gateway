class PlayersInfo {
  final int online;
  final int max;
  final List<String> list;

  const PlayersInfo({
    required this.online,
    required this.max,
    required this.list,
  });

  factory PlayersInfo.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'];
    final playerList = rawList is List
        ? rawList.map((e) => e.toString()).toList()
        : <String>[];
    return PlayersInfo(
      online: _toInt(json['online'] ?? json['count']),
      max: _toInt(json['max']),
      list: playerList,
    );
  }
}

class MemoryInfo {
  final int usedMb;
  final int maxMb;

  const MemoryInfo({required this.usedMb, required this.maxMb});

  double get usagePercent => maxMb > 0 ? usedMb / maxMb : 0.0;

  factory MemoryInfo.fromJson(Map<String, dynamic> json) {
    return MemoryInfo(
      usedMb: _toInt(json['used'] ?? json['used_mb']),
      maxMb: _toInt(json['max'] ?? json['max_mb']),
    );
  }
}

class MetricsModel {
  final bool isOnline;
  final String serverName;
  final String version;
  final PlayersInfo players;
  final double tps;
  final MemoryInfo memory;
  final double cpuUsage;
  final int uptimeSeconds;

  const MetricsModel({
    required this.isOnline,
    required this.serverName,
    required this.version,
    required this.players,
    required this.tps,
    required this.memory,
    required this.cpuUsage,
    required this.uptimeSeconds,
  });

  factory MetricsModel.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString().toLowerCase();
    final isOnline = status == 'online' || status == 'up' || status == 'running';

    final playersJson = json['players'];
    final PlayersInfo players;
    if (playersJson is Map<String, dynamic>) {
      players = PlayersInfo.fromJson(playersJson);
    } else {
      players = PlayersInfo(
        online: _toInt(json['players_online'] ?? json['online_players']),
        max: _toInt(json['players_max'] ?? json['max_players']),
        list: [],
      );
    }

    final memoryJson = json['memory'];
    final MemoryInfo memory;
    if (memoryJson is Map<String, dynamic>) {
      memory = MemoryInfo.fromJson(memoryJson);
    } else {
      memory = MemoryInfo(
        usedMb: _toInt(json['memory_used'] ?? json['used_memory']),
        maxMb: _toInt(json['memory_max'] ?? json['max_memory']),
      );
    }

    return MetricsModel(
      isOnline: isOnline,
      serverName: json['server_name']?.toString() ??
          json['name']?.toString() ??
          'Sushiski',
      version: json['version']?.toString() ?? '---',
      players: players,
      tps: _toDouble(json['tps']),
      memory: memory,
      cpuUsage: _toDouble(json['cpu_usage'] ?? json['cpu']),
      uptimeSeconds: _toInt(json['uptime'] ?? json['uptime_seconds']),
    );
  }

  // Converts a protobuf MetricsResponse (generated stub) to MetricsModel.
  // Uncomment and use once lib/src/generated/ stubs exist.
  //
  // factory MetricsModel.fromProto(dynamic /*MetricsResponse*/ proto) {
  //   return MetricsModel(
  //     isOnline: proto.isOnline,
  //     serverName: proto.serverName.isEmpty ? 'Sushiski' : proto.serverName,
  //     version: proto.version.isEmpty ? '---' : proto.version,
  //     players: PlayersInfo(
  //       online: proto.playersOnline,
  //       max: proto.playersMax,
  //       list: List<String>.from(proto.playerList),
  //     ),
  //     tps: proto.tps,
  //     memory: MemoryInfo(usedMb: proto.memoryUsedMb, maxMb: proto.memoryMaxMb),
  //     cpuUsage: proto.cpuUsage,
  //     uptimeSeconds: proto.uptimeSeconds.toInt(),
  //   );
  // }

  factory MetricsModel.offline() {
    return MetricsModel(
      isOnline: false,
      serverName: 'Sushiski',
      version: '---',
      players: const PlayersInfo(online: 0, max: 0, list: []),
      tps: 0,
      memory: const MemoryInfo(usedMb: 0, maxMb: 0),
      cpuUsage: 0,
      uptimeSeconds: 0,
    );
  }

  String get formattedUptime {
    if (uptimeSeconds <= 0) return '---';
    final d = uptimeSeconds ~/ 86400;
    final h = (uptimeSeconds % 86400) ~/ 3600;
    final m = (uptimeSeconds % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}
