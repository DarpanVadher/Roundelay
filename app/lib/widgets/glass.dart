import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// Page background that gives glass something to blur: the surface colour, two slowly drifting brand glows
/// (cobalt and sun) and a field of faint audio icons floating at different depths.
/// Glow and icon strength are kept low so text contrast on [ColorScheme.surface] holds.
/// Static under the OS reduced-motion setting.
class GlassBackdrop extends StatefulWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  State<GlassBackdrop> createState() => _GlassBackdropState();
}

class _Drifter {
  const _Drifter(
    this.icon,
    this.x,
    this.y,
    this.size,
    this.phase,
    this.loops,
    this.depth,
  );
  final IconData icon;
  final double x,
      y,
      size,
      phase; // x, y as fractions of the page; phase in turns
  final int loops; // whole loops per cycle, so the motion repeats seamlessly
  final double
  depth; // 0..1: nearer icons are bigger, brighter and travel further
}

const _drifters = [
  _Drifter(Icons.music_note_rounded, 0.10, 0.16, 46, 0.00, 1, 0.9),
  _Drifter(Icons.graphic_eq_rounded, 0.82, 0.12, 56, 0.30, 2, 0.5),
  _Drifter(Icons.speaker_rounded, 0.90, 0.46, 64, 0.55, 1, 0.8),
  _Drifter(Icons.cast_rounded, 0.06, 0.52, 52, 0.15, 2, 0.4),
  _Drifter(Icons.headphones_rounded, 0.20, 0.82, 60, 0.70, 1, 0.7),
  _Drifter(Icons.wifi_rounded, 0.70, 0.84, 48, 0.40, 2, 0.6),
  _Drifter(Icons.queue_music_rounded, 0.50, 0.06, 40, 0.85, 3, 0.3),
  _Drifter(Icons.music_note_rounded, 0.36, 0.64, 34, 0.60, 3, 0.25),
  _Drifter(Icons.equalizer_rounded, 0.62, 0.30, 36, 0.20, 2, 0.3),
];

class _GlassBackdropState extends State<GlassBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 48),
  );
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = !MediaQuery.disableAnimationsOf(context);
    if (run && !_running) {
      _c.repeat();
    } else if (!run && _running) {
      _c.stop();
    }
    _running = run;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final dark = s.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(color: s.surface),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) {
                      final t = _running ? _c.value : 0.0;
                      final a = t * 2 * math.pi;
                      return LayoutBuilder(
                        builder: (context, box) => Stack(
                          fit: StackFit.expand,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: Alignment(
                                    -1.0 + 0.35 * math.sin(a),
                                    -1.0 + 0.3 * math.cos(a),
                                  ),
                                  radius: 1.25,
                                  colors: [
                                    s.primary.withValues(
                                      alpha: dark ? 0.34 : 0.26,
                                    ),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: Alignment(
                                    1.0 - 0.3 * math.cos(a),
                                    1.0 - 0.35 * math.sin(a),
                                  ),
                                  radius: 1.05,
                                  colors: [
                                    s.tertiaryContainer.withValues(
                                      alpha: dark ? 0.2 : 0.5,
                                    ),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            for (final d in _drifters)
                              Positioned(
                                left:
                                    d.x * box.maxWidth +
                                    math.cos(
                                          a * d.loops + d.phase * 2 * math.pi,
                                        ) *
                                        18 *
                                        d.depth,
                                top:
                                    d.y * box.maxHeight +
                                    math.sin(
                                          a * d.loops + d.phase * 2 * math.pi,
                                        ) *
                                        24 *
                                        d.depth,
                                child: Transform.rotate(
                                  angle:
                                      math.sin(a * d.loops + d.phase * 6) *
                                      0.25,
                                  child: Icon(
                                    d.icon,
                                    size: d.size * (0.8 + 0.5 * d.depth),
                                    color: (dark ? s.primary : s.primary)
                                        .withValues(
                                          alpha:
                                              (dark ? 0.07 : 0.06) +
                                              0.05 * d.depth,
                                        ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// Frosted-glass card: blurred backdrop, translucent fill, hairline highlight border.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 20,
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final dark = s.brightness == Brightness.dark;
    final shape = BorderRadius.circular(widget.radius);
    final lift =
        _hover &&
        widget.onTap != null &&
        !MediaQuery.disableAnimationsOf(context);
    // Hover on desktop, focus-free on touch: a soft lift, brighter edge and brand glow.
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: lift ? 1.012 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: shape,
            boxShadow: [
              BoxShadow(
                color: s.primary.withValues(alpha: lift ? 0.22 : 0.0),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: shape,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: shape,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? [
                            Colors.white.withValues(alpha: 0.11),
                            Colors.white.withValues(alpha: 0.04),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.78),
                            Colors.white.withValues(alpha: 0.5),
                          ],
                  ),
                  border: Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: lift ? 0.32 : 0.16)
                        : Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: shape,
                    onTap: widget.onTap,
                    child: Padding(
                      padding: widget.padding ?? EdgeInsets.zero,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
