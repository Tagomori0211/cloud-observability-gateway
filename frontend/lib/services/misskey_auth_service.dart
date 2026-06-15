import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

class MisskeyUser {
  final String username;
  final String? name;
  const MisskeyUser({required this.username, this.name});
  String get displayName => (name?.isNotEmpty ?? false) ? name! : username;
}

class MisskeyAuthResult {
  final String token;
  final MisskeyUser user;
  final String host;
  const MisskeyAuthResult({
    required this.token,
    required this.user,
    required this.host,
  });
}

class MisskeyAuthService {
  static const _appName = 'Sushiski Status';

  void startAuth(String host) {
    final session = _uuid();
    final callback =
        '${Uri.base.origin}/?host=${Uri.encodeComponent(host)}';
    final url = 'https://$host/miauth/$session'
        '?name=${Uri.encodeComponent(_appName)}'
        '&callback=${Uri.encodeComponent(callback)}'
        '&permission=read:account';
    web.window.location.href = url;
  }

  ({String? session, String? host}) getPendingCallback() {
    final q = Uri.base.queryParameters;
    return (session: q['session'], host: q['host']);
  }

  void cleanCallbackUrl() {
    web.window.history.replaceState(null, '', Uri.base.path);
  }

  Future<MisskeyAuthResult?> checkSession(String host, String session) async {
    try {
      final res = await http.post(
        Uri.parse('https://$host/api/miauth/$session/check'),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] != true) return null;
      final u = data['user'] as Map<String, dynamic>;
      return MisskeyAuthResult(
        token: data['token'] as String,
        user: MisskeyUser(
          username: u['username'] as String? ?? '?',
          name: u['name'] as String?,
        ),
        host: host,
      );
    } catch (_) {
      return null;
    }
  }

  String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
