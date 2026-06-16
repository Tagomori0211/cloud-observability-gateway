import 'package:flutter/material.dart';
import '../services/account_service.dart';
import 'mypage_screen.dart';

/// MiAuthでの本人確認直後、まだパスワード未設定のユーザーが
/// ログイン用パスワードを設定するための画面。
class SetPasswordScreen extends StatefulWidget {
  final String username;

  const SetPasswordScreen({super.key, required this.username});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _service = AccountService();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (password.length < 8) {
      setState(() => _error = 'パスワードは8文字以上で設定してください');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'パスワードが一致しません');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final ok = await _service.setPassword(widget.username, password);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MyPageScreen()),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = 'パスワードの設定に失敗しました。もう一度お試しください。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'パスワードの設定',
                      style: TextStyle(
                        color: Color(0xFFF0F6FC),
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ID: ${widget.username}',
                      style: const TextStyle(
                        color: Color(0xFF6E7681),
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _PasswordField(
                      controller: _passwordCtrl,
                      label: 'パスワード（8文字以上）',
                    ),
                    const SizedBox(height: 14),
                    _PasswordField(
                      controller: _confirmCtrl,
                      label: 'パスワード（確認）',
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A4731),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF86EFAC),
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                '設定して始める',
                                style: TextStyle(
                                  color: Color(0xFFECFDF5),
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _PasswordField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: const TextStyle(color: Color(0xFFF0F6FC), fontFamily: 'monospace'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF6E7681), fontFamily: 'monospace'),
        enabledBorder: const OutlineInputBorder(),
        border: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF30363D)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF22C55E)),
        ),
      ),
    );
  }
}
