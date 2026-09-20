import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kitten/core/models/assistant_state.dart';
import 'package:kitten/core/personality/models/kitten_mood.dart';

/// Kitten's avatar, drawn entirely in code.
///
/// Being procedural rather than an asset means it scales crisply to any size,
/// needs no artwork, and can express both the [state] (what Kitten is doing)
/// and the [mood] (how Kitten feels) at once.
///
/// While idle it keeps itself alive with breathing, blinking, an occasional
/// ear twitch, and a swaying tail — and dozes off when the mood goes sleepy.
///
/// ```dart
/// KittenAvatar(
///   state: AssistantState.listening,
///   mood: KittenMood.curious,
///   size: 160,
/// )
/// ```
class KittenAvatar extends StatefulWidget {
  const KittenAvatar({
    super.key,
    this.state = AssistantState.idle,
    this.mood = KittenMood.curious,
    this.size = 160,
  });

  /// What Kitten is doing — drives the animation tempo.
  final AssistantState state;

  /// How Kitten feels — drives expression and tint.
  final KittenMood mood;

  /// Width and height of the square avatar.
  final double size;

  @override
  State<KittenAvatar> createState() => _KittenAvatarState();
}

class _KittenAvatarState extends State<KittenAvatar>
    with TickerProviderStateMixin {
  final math.Random _random = math.Random();

  late final AnimationController _breath;
  late final AnimationController _tail;
  late final AnimationController _mouth;
  late final AnimationController _blink;
  late final AnimationController _ear;

  Timer? _blinkTimer;
  Timer? _earTimer;

  /// Kitten only sleeps when it has nothing else to do.
  bool get _sleeping =>
      widget.mood == KittenMood.sleepy && widget.state == AssistantState.idle;

  @override
  void initState() {
    super.initState();

    _breath = AnimationController(vsync: this, duration: _breathDuration)
      ..repeat(reverse: true);
    _tail = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _mouth = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _ear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _syncMouth();
    _scheduleBlink();
    _scheduleEarTwitch();
  }

  @override
  void didUpdateWidget(covariant KittenAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.state != widget.state) {
      _breath.duration = _breathDuration;
      _tail.duration = _tailDuration;
      _syncMouth();
    }

    if (_sleeping != (oldWidget.mood == KittenMood.sleepy &&
        oldWidget.state == AssistantState.idle)) {
      _scheduleBlink();
      _scheduleEarTwitch();
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _earTimer?.cancel();
    _breath.dispose();
    _tail.dispose();
    _mouth.dispose();
    _blink.dispose();
    _ear.dispose();
    super.dispose();
  }

  /// A resting breath is slow; an engaged Kitten breathes faster.
  Duration get _breathDuration => switch (widget.state) {
        AssistantState.idle => const Duration(milliseconds: 2600),
        AssistantState.listening => const Duration(milliseconds: 1800),
        AssistantState.thinking => const Duration(milliseconds: 1100),
        AssistantState.speaking => const Duration(milliseconds: 1500),
      };

  Duration get _tailDuration => switch (widget.state) {
        AssistantState.idle => const Duration(milliseconds: 2600),
        AssistantState.listening => const Duration(milliseconds: 1900),
        AssistantState.thinking => const Duration(milliseconds: 1200),
        AssistantState.speaking => const Duration(milliseconds: 2100),
      };

  /// The mouth only animates while Kitten is actually talking.
  void _syncMouth() {
    if (widget.state == AssistantState.speaking) {
      if (!_mouth.isAnimating) _mouth.repeat(reverse: true);
    } else if (_mouth.isAnimating) {
      _mouth.stop();
      _mouth.value = 0;
    }
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    if (_sleeping) return;

    _blinkTimer = Timer(
      Duration(milliseconds: 2200 + _random.nextInt(3000)),
      () async {
        if (!mounted || _sleeping) return;
        await _blink.forward();
        await _blink.reverse();
        if (!mounted) return;
        _scheduleBlink();
      },
    );
  }

  void _scheduleEarTwitch() {
    _earTimer?.cancel();
    if (_sleeping) return;

    _earTimer = Timer(
      Duration(milliseconds: 3500 + _random.nextInt(5000)),
      () async {
        if (!mounted || _sleeping) return;
        await _ear.forward();
        await _ear.reverse();
        if (!mounted) return;
        _scheduleEarTwitch();
      },
    );
  }

  /// Background tint per mood, taken from the active theme.
  Color _tint(ColorScheme cs) => switch (widget.mood) {
        KittenMood.curious => cs.primaryContainer,
        KittenMood.playful => cs.tertiaryContainer,
        KittenMood.content => cs.secondaryContainer,
        KittenMood.affectionate => cs.primaryContainer,
        KittenMood.sleepy => cs.surfaceContainerHighest,
        KittenMood.concerned => cs.errorContainer,
      };

  /// A spoken description of what Kitten is doing, for screen readers.
  String get _semanticsLabel {
    // The enum labels carry display punctuation ("Listening...") that reads
    // badly aloud, so strip it.
    final doing = widget.state.label.replaceAll('.', '').trim().toLowerCase();
    return 'Kitten is $doing, feeling ${widget.mood.label.toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = _tint(cs);

    return Semantics(
      label: _semanticsLabel,
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_breath, _tail, _mouth, _blink, _ear]),
          builder: (context, _) {
            return CustomPaint(
              painter: _KittenPainter(
                tint: tint,
                sleeping: _sleeping,
                breath: _breath.value,
                tailPhase: _tail.value,
                mouthOpen: widget.mood == KittenMood.sleepy ? 0 : _mouth.value,
                blink: _sleeping ? 1 : _blink.value,
                earTwitch: _ear.value,
                mood: widget.mood,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints Kitten from primitives — no image assets involved.
class _KittenPainter extends CustomPainter {
  const _KittenPainter({
    required this.tint,
    required this.sleeping,
    required this.breath,
    required this.tailPhase,
    required this.mouthOpen,
    required this.blink,
    required this.earTwitch,
    required this.mood,
  });

  final Color tint;
  final bool sleeping;
  final double breath;
  final double tailPhase;
  final double mouthOpen;
  final double blink;
  final double earTwitch;
  final KittenMood mood;

  static const Color _fur = Color(0xFFF0A45C);
  static const Color _furShade = Color(0xFFCF7F38);
  static const Color _innerEar = Color(0xFFF3BCC8);
  static const Color _nose = Color(0xFFE58BA0);
  static const Color _dark = Color(0xFF3B2A1E);

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final Offset centre = Offset(size.width / 2, size.height / 2);

    // ── Glow and backdrop ────────────────────────────────────
    canvas.drawCircle(
      centre,
      s * 0.46,
      Paint()
        ..color = tint.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(
      centre,
      s * 0.44,
      Paint()..color = tint,
    );

    // Breathing gently scales the whole character.
    final double breathe = 1 + 0.022 * (sleeping ? breath * 1.6 : breath);
    final Offset head = Offset(
      size.width / 2,
      size.height * (sleeping ? 0.60 : 0.57),
    );
    final double headR = s * 0.27;

    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.scale(breathe);
    canvas.translate(-head.dx, -head.dy);

    _paintTail(canvas, head, headR);
    _paintEars(canvas, head, headR);
    _paintHead(canvas, head, headR);
    _paintInnerEars(canvas, head, headR);
    _paintFace(canvas, head, headR);

    canvas.restore();
  }

  void _paintTail(Canvas canvas, Offset head, double headR) {
    // The tail lives in the margin beside the head, so its reach is bounded
    // by headR rather than by the full avatar size.
    final Offset start = head + Offset(headR * 0.75, headR * 0.85);
    final double sway = sleeping
        ? 0.15
        : math.sin(tailPhase * 2 * math.pi);

    final Offset control =
        head + Offset(headR * (1.60 + sway * 0.18), headR * 0.90);
    final Offset end =
        head + Offset(headR * (1.30 + sway * 0.22), -headR * 0.25);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(control.dx, control.dy, control.dx, end.dy, end.dx, end.dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = _furShade
        ..style = PaintingStyle.stroke
        ..strokeWidth = headR * 0.23
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintEars(Canvas canvas, Offset head, double headR) {
    // A twitch lifts the ear tips a little.
    final double lift = earTwitch * headR * 0.16;

    for (final int side in <int>[-1, 1]) {
      final base = head + Offset(side * headR * 0.82, -headR * 0.52);
      final tip = head + Offset(side * headR * 0.96, -headR * 1.78 - lift);
      final inner = head + Offset(side * headR * 0.06, -headR * 1.02);

      canvas.drawPath(
        Path()
          ..moveTo(base.dx, base.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(inner.dx, inner.dy)
          ..close(),
        Paint()..color = _fur,
      );
    }
  }

  void _paintInnerEars(Canvas canvas, Offset head, double headR) {
    for (final int side in <int>[-1, 1]) {
      final base = head + Offset(side * headR * 0.72, -headR * 0.58);
      final tip = head + Offset(side * headR * 0.84, -headR * 1.52);
      final inner = head + Offset(side * headR * 0.22, -headR * 0.94);

      canvas.drawPath(
        Path()
          ..moveTo(base.dx, base.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(inner.dx, inner.dy)
          ..close(),
        Paint()..color = _innerEar,
      );
    }
  }

  void _paintHead(Canvas canvas, Offset head, double headR) {
    canvas.drawCircle(head, headR, Paint()..color = _fur);
  }

  void _paintFace(Canvas canvas, Offset head, double headR) {
    final double eyeY = head.dy - headR * 0.16;
    final double eyeDx = headR * 0.46;

    for (final int side in <int>[-1, 1]) {
      final Offset eye = Offset(head.dx + side * eyeDx, eyeY);

      if (sleeping) {
        // Closed, contented eye: a gentle downward curve.
        canvas.drawArc(
          Rect.fromCenter(
            center: eye,
            width: headR * 0.52,
            height: headR * 0.42,
          ),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = _dark
            ..style = PaintingStyle.stroke
            ..strokeWidth = headR * 0.08
            ..strokeCap = StrokeCap.round,
        );
        continue;
      }

      final double openness = 1 - blink.clamp(0.0, 1.0);
      if (openness <= 0.05) {
        canvas.drawLine(
          Offset(eye.dx - headR * 0.22, eye.dy),
          Offset(eye.dx + headR * 0.22, eye.dy),
          Paint()
            ..color = _dark
            ..strokeWidth = headR * 0.07
            ..strokeCap = StrokeCap.round,
        );
        continue;
      }

      // Mood shapes the eye: happy moods arch, worried ones narrow.
      final double eyeHeight = headR *
          (mood == KittenMood.playful || mood == KittenMood.affectionate
              ? 0.34
              : 0.38) *
          openness;

      canvas.drawOval(
        Rect.fromCenter(
          center: eye,
          width: headR * 0.44,
          height: eyeHeight,
        ),
        Paint()..color = _dark,
      );

      // A small highlight keeps the eye from looking flat.
      canvas.drawCircle(
        Offset(eye.dx - headR * 0.06, eye.dy - eyeHeight * 0.20),
        headR * 0.055 * openness,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }

    _paintMouth(canvas, head, headR);

    // Whiskers.
    final Paint whisker = Paint()
      ..color = _dark.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = headR * 0.035
      ..strokeCap = StrokeCap.round;

    for (final int side in <int>[-1, 1]) {
      for (int i = 0; i < 3; i++) {
        // Every offset is expressed in head radii so the whiskers stay put.
        canvas.drawLine(
          Offset(head.dx + side * headR * 0.30, head.dy + headR * 0.22),
          Offset(
            head.dx + side * headR * 1.25,
            head.dy + headR * (0.04 + i * 0.16),
          ),
          whisker,
        );
      }
    }

    // Blush when fond of the user.
    if (mood == KittenMood.affectionate) {
      final Paint blush = Paint()
        ..color = const Color(0xFFEE9BB0).withValues(alpha: 0.55);
      for (final int side in <int>[-1, 1]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(
              head.dx + side * headR * 0.62,
              head.dy + headR * 0.20,
            ),
            width: headR * 0.32,
            height: headR * 0.20,
          ),
          blush,
        );
      }
    }
  }

  void _paintMouth(Canvas canvas, Offset head, double headR) {
    final double noseY = head.dy + headR * 0.10;

    canvas.drawPath(
      Path()
        ..moveTo(head.dx - headR * 0.10, noseY)
        ..lineTo(head.dx + headR * 0.10, noseY)
        ..lineTo(head.dx, noseY + headR * 0.10)
        ..close(),
      Paint()..color = _nose,
    );

    final double mouthY = noseY + headR * 0.12;

    if (mouthOpen > 0.02) {
      // Talking: an open mouth whose size follows the voice.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(head.dx, mouthY + headR * 0.06),
          width: headR * (0.20 + 0.10 * mouthOpen),
          height: headR * (0.06 + 0.18 * mouthOpen),
        ),
        Paint()..color = _dark,
      );
      return;
    }

    final Paint line = Paint()
      ..color = _dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = headR * 0.055
      ..strokeCap = StrokeCap.round;

    // A resting cat mouth: two small curves meeting under the nose.
    for (final int side in <int>[-1, 1]) {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(head.dx + side * headR * 0.12, mouthY + headR * 0.03),
          width: headR * 0.26,
          height: headR * 0.20,
        ),
        0,
        math.pi,
        false,
        line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _KittenPainter oldDelegate) =>
      oldDelegate.tint != tint ||
      oldDelegate.sleeping != sleeping ||
      oldDelegate.mood != mood ||
      oldDelegate.breath != breath ||
      oldDelegate.tailPhase != tailPhase ||
      oldDelegate.mouthOpen != mouthOpen ||
      oldDelegate.blink != blink ||
      oldDelegate.earTwitch != earTwitch;
}
