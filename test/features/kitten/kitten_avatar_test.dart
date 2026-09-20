import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/models/assistant_state.dart';
import 'package:kitten/core/personality/models/kitten_mood.dart';
import 'package:kitten/features/kitten/presentation/widgets/kitten_avatar.dart';

void main() {
  Future<void> pumpAvatar(
    WidgetTester tester, {
    required AssistantState state,
    required KittenMood mood,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: KittenAvatar(state: state, mood: mood, size: 140),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets('paints every state and mood combination without error',
      (tester) async {
    for (final state in AssistantState.values) {
      for (final mood in KittenMood.values) {
        await pumpAvatar(tester, state: state, mood: mood);
        expect(
          tester.takeException(),
          isNull,
          reason: 'state=$state mood=$mood should paint cleanly',
        );
      }
    }
  });

  testWidgets('animates over time without throwing', (tester) async {
    await pumpAvatar(
      tester,
      state: AssistantState.speaking,
      mood: KittenMood.playful,
    );

    // Drive several frames so the breathing, tail, and mouth loops all run.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('describes itself for screen readers', (tester) async {
    // Semantics are only built when something is listening for them.
    final handle = tester.ensureSemantics();

    await pumpAvatar(
      tester,
      state: AssistantState.listening,
      mood: KittenMood.affectionate,
    );

    expect(
      find.bySemanticsLabel('Kitten is listening, feeling affectionate'),
      findsOneWidget,
    );

    handle.dispose();
  });
}
