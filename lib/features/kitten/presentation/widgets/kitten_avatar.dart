import 'package:flutter/material.dart';

import 'package:kitten/core/models/assistant_state.dart';

/// A reusable, self-contained kitten avatar widget.
///
/// Displays a placeholder cat face that subtly animates based on the
/// current [AssistantState]. Designed to be swapped out later for a
/// Lottie/Rive animation without changing calling code.
///
/// ```dart
/// KittenAvatar(
///   state: AssistantState.idle,
///   size: 160,
/// )
/// ```
class KittenAvatar extends StatefulWidget {
  const KittenAvatar({
    super.key,
    this.state = AssistantState.idle,
    this.size = 160,
  });

  /// The current assistant state — controls visual appearance.
  final AssistantState state;

  /// Diameter of the avatar circle.
  final double size;

  @override
  State<KittenAvatar> createState() => _KittenAvatarState();
}

class _KittenAvatarState extends State<KittenAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant KittenAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimationSpeed();
  }

  void _updateAnimationSpeed() {
    switch (widget.state) {
      case AssistantState.idle:
        _controller.duration = const Duration(milliseconds: 1800);
      case AssistantState.listening:
        _controller.duration = const Duration(milliseconds: 1000);
      case AssistantState.thinking:
        _controller.duration = const Duration(milliseconds: 600);
      case AssistantState.speaking:
        _controller.duration = const Duration(milliseconds: 900);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Visual mapping per state ─────────────────────────────
  String get _face {
    return switch (widget.state) {
      AssistantState.idle => '😺',
      AssistantState.listening => '🐱',
      AssistantState.thinking => '😼',
      AssistantState.speaking => '😸',
    };
  }

  Color _glowColor(ColorScheme cs) {
    return switch (widget.state) {
      AssistantState.idle => cs.primaryContainer,
      AssistantState.listening => cs.tertiaryContainer,
      AssistantState.thinking => cs.secondaryContainer,
      AssistantState.speaking => cs.primaryContainer,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _glowColor(cs),
          boxShadow: [
            BoxShadow(
              color: _glowColor(cs).withValues(alpha: 0.4),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          _face,
          style: TextStyle(fontSize: widget.size * 0.45),
        ),
      ),
    );
  }
}
