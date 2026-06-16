import 'dart:convert';
import 'package:http/browser_client.dart';
import '../models/user_profile.dart';
import '../models/linked_account.dart';

class AccountService {
  final _client = BrowserClient()..withCredentials = true;

  Future<({UserProfile user, List<LinkedAccount> accounts})?> getMe() async {
    try {
      final res = await _client.get(Uri.parse('/api/me'));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      
      final user = UserProfile.fromJson(data['user'] as Map<String, dynamic>);
      final list = (data['accounts'] as List<dynamic>)
          .map((e) => LinkedAccount.fromJson(e as Map<String, dynamic>))
          .toList();

      return (user: user, accounts: list);
    } catch (_) {
      return null;
    }
  }

  Future<LinkedAccount?> linkAccount(String edition, String ign) async {
    try {
      final res = await _client.post(
        Uri.parse('/api/me/accounts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'edition': edition, 'ign': ign}),
      );
      if (res.statusCode != 201) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return LinkedAccount.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<bool> unlinkAccount(int id) async {
    try {
      final res = await _client.delete(Uri.parse('/api/me/accounts/$id'));
      return res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<bool> logout() async {
    try {
      final res = await _client.post(Uri.parse('/api/logout'));
      return res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
