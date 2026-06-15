import 'dart:math';
import 'package:flutter/material.dart';
import '../services/misskey_auth_service.dart';
import 'status_screen.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _service = MisskeyAuthService();

  late final AnimationController _entranceCtrl;
  late final Animation<double> _logoOpacity;
  late final Animation<Offset> _logoSlide;
  late final Animation<double> _formOpacity;
  late final Animation<Offset> _formSlide;

  bool _checking = false;
  bool _redirecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _logoOpacity = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    ));

    _formOpacity = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );
    _formSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
    ));

    _entranceCtrl.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) => _handleCallback());
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleCallback() async {
    final cb = _service.getPendingCallback();
    if (cb.session == null || cb.host == null) return;

    _service.cleanCallbackUrl();
    setState(() => _checking = true);

    final result = await _service.checkSession(cb.host!, cb.session!);
    if (!mounted) return;

    if (result != null) {
      _goToDashboard();
    } else {
      setState(() {
        _checking = false;
        _error = '認証に失敗しました。もう一度お試しください。';
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _redirecting = true;
      _error = null;
    });
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    _service.startAuth('Sushi.ski');
  }

  void _goToDashboard() {
    Navigator.of(context).pushReplacement(
      _PortalRevealRoute(page: const StatusScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          const _AnimatedBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SlideTransition(
                        position: _logoSlide,
                        child: FadeTransition(
                          opacity: _logoOpacity,
                          child: const _LogoSection(),
                        ),
                      ),
                      const SizedBox(height: 44),
                      SlideTransition(
                        position: _formSlide,
                        child: FadeTransition(
                          opacity: _formOpacity,
                          child: _LoginCard(
                            loading: _redirecting,
                            error: _error,
                            onLogin: _login,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_checking) const _AuthCheckOverlay(),
        ],
      ),
    );
  }
}

// ─── Logo ─────────────────────────────────────────────────────────────────────

class _LogoSection extends StatelessWidget {
  const _LogoSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _GrassBlockIcon(size: 72),
        const SizedBox(height: 24),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF6FCF72), Color(0xFF22C55E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'TAGOMORI',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 7,
              shadows: [
                Shadow(
                  color: Color(0xFF004400),
                  offset: Offset(3, 3),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'S T A T U S',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
            letterSpacing: 7,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Minecraft Server Monitor',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: Color(0xFF374151),
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

// ─── Login Card ───────────────────────────────────────────────────────────────

class _LoginCard extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback onLogin;

  const _LoginCard({
    required this.loading,
    required this.error,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border.all(color: const Color(0xFF30363D)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x60000000),
            blurRadius: 32,
            spreadRadius: 4,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.cloud_outlined,
                  color: Color(0xFF86EFAC), size: 20),
              SizedBox(width: 10),
              Text(
                'Misskey でログイン',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontFamily: 'monospace',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Sushi.ski アカウントで認証します',
            style: TextStyle(
              color: Color(0xFF6E7681),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 28),

          // Login button
          SizedBox(
            width: double.infinity,
            child: _MinecraftButton(
              label: 'MiAuth でログイン',
              onPressed: loading ? null : onLogin,
              loading: loading,
            ),
          ),

          // Error
          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF3D0C0C),
                border: Border.all(
                    color: const Color(0xFF7F1D1D).withValues(alpha: 0.8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Color(0xFFFCA5A5), size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(color: Color(0xFF21262D), thickness: 1, height: 1),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              'powered by Misskey MiAuth',
              style: TextStyle(
                color: Color(0xFF3D4451),
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Minecraft Button ─────────────────────────────────────────────────────────

class _MinecraftButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const _MinecraftButton({
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  State<_MinecraftButton> createState() => _MinecraftButtonState();
}

class _MinecraftButtonState extends State<_MinecraftButton> {
  bool _hovered = false;
  bool _pressed = false;

  static const _face = Color(0xFF1A4731);
  static const _faceHover = Color(0xFF22543D);
  static const _highlight = Color(0xFF2F9E5A);
  static const _shadow = Color(0xFF102B1E);
  static const _faceDisabled = Color(0xFF111D17);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final face = !enabled ? _faceDisabled : (_hovered ? _faceHover : _face);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed!();
              }
            : null,
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          height: 48,
          transform:
              _pressed ? Matrix4.translationValues(0, 2, 0) : Matrix4.identity(),
          decoration: BoxDecoration(
            color: face,
            border: _pressed
                ? Border.all(color: _shadow, width: 2)
                : Border(
                    top: BorderSide(
                        color: enabled
                            ? _highlight
                            : _highlight.withValues(alpha: 0.3),
                        width: 2),
                    left: BorderSide(
                        color: enabled
                            ? _highlight
                            : _highlight.withValues(alpha: 0.3),
                        width: 2),
                    bottom: BorderSide(color: _shadow, width: 2),
                    right: BorderSide(color: _shadow, width: 2),
                  ),
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Color(0xFF86EFAC),
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.login,
                        color: enabled
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFF2D4A38),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: enabled
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFF2D4A38),
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          shadows: enabled
                              ? const [
                                  Shadow(
                                    color: Color(0xFF052E16),
                                    offset: Offset(1, 1),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Grass Block Icon ─────────────────────────────────────────────────────────

class _GrassBlockIcon extends StatelessWidget {
  final double size;
  const _GrassBlockIcon({this.size = 48});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GrassBlockPainter(),
    );
  }
}

class _GrassBlockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    void px(double gx, double gy, double gw, double gh, Color c) {
      canvas.drawRect(
        Rect.fromLTWH(gx * s.width / 16, gy * s.height / 16,
            gw * s.width / 16, gh * s.height / 16),
        Paint()..color = c,
      );
    }

    // Dirt base
    px(0, 4, 16, 12, const Color(0xFF8B5E3C));

    // Dirt texture (darker patches)
    for (final p in [
      [1, 6], [4, 5], [7, 8], [10, 6], [13, 9],
      [2, 11], [6, 13], [11, 12], [14, 7], [3, 14],
    ]) {
      px(p[0].toDouble(), p[1].toDouble(), 1, 1, const Color(0xFF6B4226));
    }

    // Grass top
    px(0, 0, 16, 5, const Color(0xFF55A630));

    // Grass dark patches
    for (final p in [
      [0, 0], [2, 1], [5, 0], [8, 2], [11, 0], [14, 1],
      [1, 3], [4, 2], [7, 3], [10, 2], [13, 3], [15, 1],
    ]) {
      px(p[0].toDouble(), p[1].toDouble(), 1, 1, const Color(0xFF3D7A23));
    }

    // Grass-dirt seam
    px(0, 4, 16, 1, const Color(0xFF6DBF3E));

    // Top-left edge highlight
    final hl = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = s.width / 32;
    canvas.drawLine(Offset(0, 0), Offset(s.width, 0), hl);
    canvas.drawLine(Offset(0, 0), Offset(0, s.height), hl);

    // Bottom-right edge shadow
    final sh = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = s.width / 32;
    canvas.drawLine(Offset(0, s.height), Offset(s.width, s.height), sh);
    canvas.drawLine(Offset(s.width, 0), Offset(s.width, s.height), sh);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─── Animated Background ──────────────────────────────────────────────────────

class _AnimatedBackground extends StatefulWidget {
  const _AnimatedBackground();

  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_BlockData> _blocks;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();

    final rand = Random(42);
    const colors = [
      Color(0xFF1A3A0E), Color(0xFF3A3A3A), Color(0xFF5C3D1E),
      Color(0xFF122A12), Color(0xFF24243A), Color(0xFF0E2A0E),
    ];
    _blocks = List.generate(22, (i) => _BlockData(
      x: rand.nextDouble(),
      baseY: rand.nextDouble(),
      size: 4 + rand.nextInt(14).toDouble(),
      speed: 0.08 + rand.nextDouble() * 0.45,
      color: colors[i % colors.length],
      opacity: 0.07 + rand.nextDouble() * 0.18,
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _BgPainter(blocks: _blocks, time: _ctrl.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BlockData {
  final double x, baseY, size, speed, opacity;
  final Color color;
  const _BlockData({
    required this.x,
    required this.baseY,
    required this.size,
    required this.speed,
    required this.color,
    required this.opacity,
  });
}

class _BgPainter extends CustomPainter {
  final List<_BlockData> blocks;
  final double time;
  const _BgPainter({required this.blocks, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    // Grid
    final gp = Paint()
      ..color = const Color(0xFF141E14)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gp);
    }
    for (double y = 0; y < size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }

    // Floating pixel blocks
    for (final b in blocks) {
      final x = b.x * size.width;
      final frac = ((b.baseY - time * b.speed) % 1.0 + 1.0) % 1.0;
      final y = frac * size.height;
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(x, y), width: b.size, height: b.size),
        Paint()..color = b.color.withValues(alpha: b.opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.time != time;
}

// ─── Auth Check Overlay ───────────────────────────────────────────────────────

class _AuthCheckOverlay extends StatelessWidget {
  const _AuthCheckOverlay();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xE00D1117),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GrassBlockIcon(size: 56),
            SizedBox(height: 28),
            CircularProgressIndicator(
              color: Color(0xFF22C55E),
              strokeWidth: 2,
            ),
            SizedBox(height: 18),
            Text(
              '認証確認中...',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontFamily: 'monospace',
                fontSize: 14,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Portal Reveal Page Route ─────────────────────────────────────────────────

class _PortalRevealRoute extends PageRouteBuilder {
  _PortalRevealRoute({required Widget page})
      : super(
          pageBuilder: (_, _, _) => page,
          transitionDuration: const Duration(milliseconds: 750),
          reverseTransitionDuration: const Duration(milliseconds: 350),
        );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final size = MediaQuery.of(context).size;
    final maxR =
        sqrt(size.width * size.width + size.height * size.height) / 2 + 10;
    final center = Offset(size.width / 2, size.height / 2);

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );

    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (_, child) {
        final t = curved.value;
        final r = t * maxR;

        return Stack(
          children: [
            CustomPaint(
              painter: _GlowRingPainter(center: center, radius: r),
              child: const SizedBox.expand(),
            ),
            ClipPath(
              clipper: _CircleClipper(center: center, radius: r),
              child: child!,
            ),
          ],
        );
      },
    );
  }
}

class _GlowRingPainter extends CustomPainter {
  final Offset center;
  final double radius;
  const _GlowRingPainter({required this.center, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    if (radius < 1) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF22C55E).withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  @override
  bool shouldRepaint(_GlowRingPainter old) =>
      old.radius != radius || old.center != center;
}

class _CircleClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;
  const _CircleClipper({required this.center, required this.radius});

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.radius != radius || old.center != center;
}
