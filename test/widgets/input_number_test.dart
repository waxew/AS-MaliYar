import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waterflyiii/widgets/input_number.dart';

/// Comprehensive test suite for NumberInput widget with math evaluation.
///
/// Tests cover:
/// - Basic number input
/// - Math expression input and evaluation
/// - Chained calculations (evaluates when second operator is pressed)
/// - Enter key evaluation
/// - Focus loss evaluation
/// - Input validation and formatting
void main() {
  group('NumberInput Widget', () {
    testWidgets('displays number input field', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(controller: controller, decimals: 2),
          ),
        ),
      );

      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('allows basic number input', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(controller: controller, decimals: 2),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);
      await tester.enterText(textField, '123.45');
      await tester.pump();

      expect(controller.text, '123.45');
    });

    testWidgets('replaces comma with dot for decimals', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(controller: controller, decimals: 2),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);
      await tester.enterText(textField, '123,45');
      await tester.pump();

      expect(controller.text, '123.45');
    });

    testWidgets('allows math operators when math evaluation enabled', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              controller: controller,
              decimals: 2,
              enableMathEvaluation: true,
            ),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);
      await tester.enterText(textField, '10+5');
      await tester.pump();

      expect(controller.text, '10+5');
    });

    testWidgets('prevents consecutive operators', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      controller.text = '10+';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              controller: controller,
              decimals: 2,
              enableMathEvaluation: true,
            ),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);
      await tester.tap(textField);
      await tester.pump();

      // Try to add another operator - should be prevented
      await tester.enterText(textField, '10++');
      await tester.pump();

      // Should not have consecutive operators
      expect(controller.text, isNot(contains('++')));
    });

    testWidgets('evaluates expression on Enter key', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              controller: controller,
              decimals: 2,
              enableMathEvaluation: true,
            ),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);
      await tester.enterText(textField, '10+5');
      await tester.pump();

      // Simulate Enter key press
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Expression should be evaluated
      expect(controller.text, '15.00');
    });

    testWidgets('evaluates expression on focus loss', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      final FocusNode focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                NumberInput(
                  controller: controller,
                  focusNode: focusNode,
                  decimals: 2,
                  enableMathEvaluation: true,
                ),
                // Another widget to focus on
                const TextField(key: Key('other_field')),
              ],
            ),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField).first;
      await tester.enterText(textField, '10+5');
      await tester.pump();

      // Focus on another field
      final Finder otherField = find.byKey(const Key('other_field'));
      await tester.tap(otherField);
      await tester.pump();

      // Expression should be evaluated
      expect(controller.text, '15.00');
    });

    testWidgets('handles chained calculations', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              controller: controller,
              decimals: 2,
              enableMathEvaluation: true,
            ),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);

      // Type "10+5" - should not evaluate yet
      await tester.enterText(textField, '10+5');
      await tester.pump();
      expect(controller.text, '10+5');

      // Add "*" - should evaluate "10+5" to 15, then add "*"
      await tester.enterText(textField, '10+5*');
      await tester.pump();

      // Should have evaluated and added the operator
      expect(controller.text, startsWith('15'));
      expect(controller.text, endsWith('*'));
    });

    testWidgets('formats result with correct decimal places', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              controller: controller,
              decimals: 2,
              enableMathEvaluation: true,
            ),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);
      await tester.enterText(textField, '10/3');
      await tester.pump();

      // Simulate Enter key
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Should format with 2 decimal places
      expect(controller.text, '3.33');
    });

    testWidgets('handles invalid expressions gracefully', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      controller.text = '10+5';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              controller: controller,
              decimals: 2,
              enableMathEvaluation: true,
            ),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);

      // Try to enter invalid expression
      await tester.enterText(textField, '10++5');
      await tester.pump();

      // Should not have consecutive operators
      expect(controller.text, isNot(contains('++')));
    });

    testWidgets('disables math evaluation when flag is false', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              controller: controller,
              decimals: 2,
              enableMathEvaluation: false,
            ),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);

      // Try to enter operator - should be rejected
      await tester.enterText(textField, '10+5');
      await tester.pump();

      // Should not contain operators
      expect(controller.text, isNot(contains('+')));
    });

    testWidgets('calls onChanged callback', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      String? lastChangedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              controller: controller,
              decimals: 2,
              onChanged: (String value) {
                lastChangedValue = value;
              },
            ),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);
      await tester.enterText(textField, '123');
      await tester.pump();

      expect(lastChangedValue, '123');
    });

    testWidgets('respects disabled state', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      controller.text = '123';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              controller: controller,
              decimals: 2,
              disabled: true,
            ),
          ),
        ),
      );

      final Finder textField = find.byType(TextFormField);
      final TextFormField field = tester.widget<TextFormField>(textField);

      // Check that the field is disabled (readOnly is not directly accessible)
      expect(field.enabled, false);
    });
  });
}
