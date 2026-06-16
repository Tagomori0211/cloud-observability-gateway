import 'package:flutter/material.dart';
import '../services/account_service.dart';
import '../models/user_profile.dart';
import '../models/linked_account.dart';
import 'status_screen.dart';
import 'login_screen.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final _service = AccountService();
  bool _loading = true;
  UserProfile? _user;
  List<LinkedAccount> _accounts = [];
  String? _error;

  final _ignController = TextEditingController();
  String _selectedEdition = 'java';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _ignController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _service.getMe();
    if (!mounted) return;
    if (res != null) {
      setState(() {
        _user = res.user;
        _accounts = res.accounts;
        _loading = false;
        _submitting = false;
      });
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _link() async {
    final ign = _ignController.text.trim();
    if (ign.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final res = await _service.linkAccount(_selectedEdition, ign);
    if (!mounted) return;

    if (res != null) {
      _ignController.clear();
      _fetchData();
    } else {
      setState(() {
        _submitting = false;
        _error = '連携に失敗しました。IGNの形式が正しくないか、既に登録されている可能性があります。';
      });
    }
  }

  Future<void> _unlink(int id) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final success = await _service.unlinkAccount(id);
    if (!mounted) return;
    if (success) {
      _fetchData();
    } else {
      setState(() {
        _loading = false;
        _error = '連携の解除に失敗しました。';
      });
    }
  }

  Future<void> _logout() async {
    setState(() => _loading = true);
    await _service.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1117),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF22C55E)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: const Text(
          'マイページ',
          style: TextStyle(
            color: Color(0xFFF0F6FC),
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFFCA5A5)),
            onPressed: _logout,
            tooltip: 'ログアウト',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUserCard(),
                const SizedBox(height: 24),
                _buildAccountsSection(),
                const SizedBox(height: 24),
                _buildLinkForm(),
                const SizedBox(height: 32),
                _buildMetricsLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle, size: 64, color: Color(0xFF86EFAC)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '@${_user?.username ?? ""}',
                style: const TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Host: ${_user?.misskeyHost ?? ""}',
                style: const TextStyle(
                  color: Color(0xFF8B949E),
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '連携中のゲーム内アカウント(IGN)',
            style: TextStyle(
              color: Color(0xFFF0F6FC),
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (_accounts.isEmpty)
            const Text(
              '連携しているアカウントはありません。',
              style: TextStyle(color: Color(0xFF8B949E), fontFamily: 'monospace'),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _accounts.length,
              separatorBuilder: (_, __) => const Divider(color: Color(0xFF30363D)),
              itemBuilder: (context, index) {
                final acc = _accounts[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    acc.edition == 'java' ? Icons.computer : Icons.phone_android,
                    color: const Color(0xFF86EFAC),
                  ),
                  title: Text(
                    acc.ign,
                    style: const TextStyle(
                      color: Color(0xFFF0F6FC),
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'エディション: ${acc.edition.toUpperCase()} / 連携日: ${acc.linkedAt.toLocal().toString().substring(0, 10)}',
                    style: const TextStyle(
                      color: Color(0xFF8B949E),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFFCA5A5)),
                    onPressed: () => _unlink(acc.id),
                    tooltip: '連携解除',
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLinkForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '新しいゲーム内アカウントを連携する',
            style: TextStyle(
              color: Color(0xFFF0F6FC),
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedEdition,
                  dropdownColor: const Color(0xFF161B22),
                  decoration: const InputDecoration(
                    labelText: 'エディション',
                    labelStyle: TextStyle(color: Color(0xFF8B949E), fontFamily: 'monospace'),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF30363D)),
                    ),
                  ),
                  style: const TextStyle(color: Color(0xFFF0F6FC), fontFamily: 'monospace'),
                  items: const [
                    DropdownMenuItem(value: 'java', child: Text('Java')),
                    DropdownMenuItem(value: 'bedrock', child: Text('Bedrock')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedEdition = val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _ignController,
                  decoration: const InputDecoration(
                    labelText: 'ゲーム内ユーザー名 (IGN)',
                    labelStyle: TextStyle(color: Color(0xFF8B949E), fontFamily: 'monospace'),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF30363D)),
                    ),
                  ),
                  style: const TextStyle(color: Color(0xFFF0F6FC), fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFCA5A5), fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: const Text('アカウントを連携する'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A4731),
                foregroundColor: const Color(0xFFECFDF5),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
              ),
              onPressed: _submitting ? null : _link,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsLink() {
    return Center(
      child: TextButton.icon(
        icon: const Icon(Icons.dashboard_outlined, color: Color(0xFF86EFAC)),
        label: const Text(
          'サーバーリアルタイムステータスを見る',
          style: TextStyle(
            color: Color(0xFF86EFAC),
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StatusScreen()),
          );
        },
      ),
    );
  }
}
