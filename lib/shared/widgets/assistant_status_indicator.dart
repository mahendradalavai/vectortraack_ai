import 'package:flutter/material.dart';

import 'package:kitten/core/models/assistant_state.dart';

/// Displays a small chip showing the current [AssistantState].
class AssistantStatusIndicator extends StatelessWidget {
  const AssistantStatusIndicator({
    super.key,
    required this.state,
  });

  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(state.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            'Assistant: ${state.label}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
