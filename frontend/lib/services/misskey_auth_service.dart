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

class MisskeyAuthService {
  static const _appName = 'Tagomori Status';

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

  Future<MisskeyUser?> completeLogin(String session) async {
    try {
      final res = await http.post(
        Uri.parse('/api/auth/miauth/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session': session}),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return MisskeyUser(
        username: data['username'] as String? ?? '?',
        name: null, // バックエンドからの応答に合わせて null に設定 (必要に応じて response.name などから)
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
