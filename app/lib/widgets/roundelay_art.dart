import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Roundelay mark as a living illustration: rings pulse outward from the sun dot.
/// With [orbiters] > 0, small device dots travel round the outer ring (used where we wait for devices).
/// Stays still (one calm frame) when the platform asks for reduced motion.
class RoundelayArt extends StatefulWidget {
  const RoundelayArt({
    super.key,
    this.size = 160,
    this.orbiters = 0,
    this.animate = true,
  });
  final double size;
  final int orbiters;
  final bool animate;

  @override
  State<RoundelayArt> createState() => _RoundelayArtState();
}

class _RoundelayArtState extends State<RoundelayArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  bool _running = false;

  bool _shouldRun(BuildContext context) =>
      widget.animate && !MediaQuery.disableAnimationsOf(context);

  void _sync() {
    final run = _shouldRun(context);
    if (run && !_running) {
      _c.repeat();
    } else if (!run && _running) {
      _c.stop();
    }
    _running = run;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(RoundelayArt old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _ArtPainter(
              t: _running ? _c.value : 0.12,
              ring: s.primary,
              dot: s.tertiaryContainer,
              orbit: s.secondary,
              orbiters: widget.orbiters,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter({
    required this.t,
    required this.ring,
    required this.dot,
    required this.orbit,
    required this.orbiters,
  });
  final double t;
  final Color ring, dot, orbit;
  final int orbiters;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final u = size.width / 108;
    final stroke = Paint()..style = PaintingStyle.stroke;

    // Outward ripples: three staggered waves expanding past the outer ring and fading.
    for (var i = 0; i < 3; i++) {
      final p = (t * 2 + i / 3) % 1.0;
      stroke
        ..strokeWidth = 2.2 * u
        ..color = ring.withValues(alpha: 0.3 * (1 - p));
      canvas.drawCircle(c, (13.5 + p * 38) * u, stroke);
    }
    // The two fixed rings, as in the app icon.
    stroke
      ..strokeWidth = 5 * u
      ..color = ring;
    canvas.drawCircle(c, 24 * u, stroke);
    canvas.drawCircle(c, 13.5 * u, stroke);

    // Devices travelling round the outer ring.
    for (var i = 0; i < orbiters; i++) {
      final a = (t + i / orbiters) * 2 * math.pi - math.pi / 2;
      final p = c + Offset(math.cos(a), math.sin(a)) * (24 * u);
      canvas.drawCircle(p, 6.5 * u, Paint()..color = orbit);
      canvas.drawCircle(p, 3 * u, Paint()..color = dot);
    }
    // Breathing sun dot.
    final pulse = 1 + 0.12 * math.sin(t * 2 * math.pi * 3);
    canvas.drawCircle(c, 5 * u * pulse, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_ArtPainter o) =>
      o.t != t ||
      o.ring != ring ||
      o.dot != dot ||
      o.orbit != orbit ||
      o.orbiters != orbiters;
}

/// Fades and slides its child in once, after [delay]. Instant under reduced motion.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _run = Duration(milliseconds: 450);
  // The delay is part of the timeline (no Timer), so widget tests never see a pending timer.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _run + widget.delay,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMilliseconds / (_run + widget.delay).inMilliseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(_curve),
      child: widget.child,
    ),
  );
}
