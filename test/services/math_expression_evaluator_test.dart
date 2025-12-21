import 'package:flutter_test/flutter_test.dart';
import 'package:waterflyiii/services/math_expression_evaluator.dart';

/// Comprehensive test suite for MathExpressionEvaluator.
///
/// Tests cover:
/// - Basic arithmetic operations (+, -, *, /)
/// - Operator precedence (multiplication/division before addition/subtraction)
/// - Decimal number handling
/// - Partial expression evaluation for chained calculations
/// - Error handling (invalid expressions, division by zero)
/// - Edge cases (empty expressions, single numbers, negative numbers)
void main() {
  group('MathExpressionEvaluator', () {
    late MathExpressionEvaluator evaluator;

    setUp(() {
      evaluator = MathExpressionEvaluator();
    });

    group('Basic arithmetic operations', () {
      test('addition', () {
        expect(evaluator.evaluate('10+5'), 15.0);
        expect(evaluator.evaluate('1+2+3'), 6.0);
        expect(evaluator.evaluate('0+0'), 0.0);
      });

      test('subtraction', () {
        expect(evaluator.evaluate('10-5'), 5.0);
        expect(evaluator.evaluate('5-10'), -5.0);
        expect(evaluator.evaluate('10-5-2'), 3.0);
      });

      test('multiplication', () {
        expect(evaluator.evaluate('10*5'), 50.0);
        expect(evaluator.evaluate('2*3*4'), 24.0);
        expect(evaluator.evaluate('0*5'), 0.0);
      });

      test('division', () {
        expect(evaluator.evaluate('10/5'), 2.0);
        expect(evaluator.evaluate('15/3'), 5.0);
        expect(evaluator.evaluate('1/2'), 0.5);
      });
    });

    group('Operator precedence', () {
      test('multiplication before addition', () {
        expect(evaluator.evaluate('10+5*2'), 20.0); // 10 + (5*2) = 20
        expect(evaluator.evaluate('2+3*4'), 14.0); // 2 + (3*4) = 14
      });

      test('division before addition', () {
        expect(evaluator.evaluate('10+20/4'), 15.0); // 10 + (20/4) = 15
        expect(evaluator.evaluate('2+8/2'), 6.0); // 2 + (8/2) = 6
      });

      test('multiplication before subtraction', () {
        expect(evaluator.evaluate('10-5*2'), 0.0); // 10 - (5*2) = 0
        expect(evaluator.evaluate('20-3*4'), 8.0); // 20 - (3*4) = 8
      });

      test('division before subtraction', () {
        expect(evaluator.evaluate('20-8/2'), 16.0); // 20 - (8/2) = 16
        expect(evaluator.evaluate('10-15/3'), 5.0); // 10 - (15/3) = 5
      });

      test('multiple operations with precedence', () {
        expect(evaluator.evaluate('10+5*2-3'), 17.0); // 10 + 10 - 3 = 17
        expect(evaluator.evaluate('2*3+4*5'), 26.0); // 6 + 20 = 26
        expect(evaluator.evaluate('20/4+10/2'), 10.0); // 5 + 5 = 10
      });
    });

    group('Decimal numbers', () {
      test('addition with decimals', () {
        expect(evaluator.evaluate('10.5+5.2'), 15.7);
        expect(evaluator.evaluate('1.1+2.2'), closeTo(3.3, 0.0001));
      });

      test('subtraction with decimals', () {
        expect(evaluator.evaluate('10.5-5.2'), 5.3);
        expect(evaluator.evaluate('3.3-1.1'), closeTo(2.2, 0.0001));
      });

      test('multiplication with decimals', () {
        expect(evaluator.evaluate('10.5*2'), 21.0);
        expect(evaluator.evaluate('2.5*4'), 10.0);
      });

      test('division with decimals', () {
        expect(evaluator.evaluate('10.5/2'), 5.25);
        expect(evaluator.evaluate('7.5/3'), 2.5);
      });

      test('comma as decimal separator', () {
        expect(evaluator.evaluate('10,5+5,2'), 15.7);
        expect(evaluator.evaluate('3,3-1,1'), closeTo(2.2, 0.0001));
      });
    });

    group('Negative numbers', () {
      test('leading minus', () {
        expect(evaluator.evaluate('-10+5'), -5.0);
        expect(evaluator.evaluate('-5*2'), -10.0);
        expect(evaluator.evaluate('-10/2'), -5.0);
      });

      test('subtraction resulting in negative', () {
        expect(evaluator.evaluate('5-10'), -5.0);
        expect(evaluator.evaluate('1-5'), -4.0);
      });
    });

    group('Partial expression evaluation', () {
      test('evaluates up to last operator', () {
        expect(evaluator.evaluatePartial('10+5*'), 15.0);
        expect(evaluator.evaluatePartial('10+5+'), 15.0);
        expect(evaluator.evaluatePartial('10*2+'), 20.0);
      });

      test('handles trailing operator', () {
        expect(evaluator.evaluatePartial('10+'), 10.0);
        expect(evaluator.evaluatePartial('10-'), 10.0);
        expect(evaluator.evaluatePartial('10*'), 10.0);
        expect(evaluator.evaluatePartial('10/'), 10.0);
      });

      test('handles complex partial expressions', () {
        expect(evaluator.evaluatePartial('10+5*2+'), 20.0); // 10 + (5*2) = 20
        expect(
          evaluator.evaluatePartial('2*3+4*'),
          10.0,
        ); // 2*3+4 = 10 (evaluates before last operator)
      });

      test('returns null for invalid partial expressions', () {
        expect(evaluator.evaluatePartial(''), null);
        expect(evaluator.evaluatePartial('+'), null);
        expect(evaluator.evaluatePartial('++'), null);
      });
    });

    group('Validation', () {
      test('valid expressions', () {
        expect(evaluator.isValidExpression('10+5'), true);
        expect(evaluator.isValidExpression('10.5+5.2'), true);
        expect(evaluator.isValidExpression('10*5+2'), true);
        expect(evaluator.isValidExpression('-10+5'), true);
      });

      test('invalid expressions', () {
        expect(evaluator.isValidExpression(''), false);
        expect(evaluator.isValidExpression('++'), false);
        expect(evaluator.isValidExpression('10++5'), false);
        expect(evaluator.isValidExpression('10/0'), false);
        expect(evaluator.isValidExpression('abc'), false);
        expect(evaluator.isValidExpression('10+'), false); // Trailing operator
      });

      test('division by zero detection', () {
        expect(evaluator.isValidExpression('10/0'), false);
        expect(evaluator.isValidExpression('10/0.5'), true); // 0.5 is valid
        expect(evaluator.isValidExpression('10+5/0'), false);
      });
    });

    group('Error handling', () {
      test('returns null for empty expression', () {
        expect(evaluator.evaluate(''), null);
      });

      test('returns null for invalid expressions', () {
        expect(evaluator.evaluate('++'), null);
        expect(evaluator.evaluate('10++5'), null);
        expect(evaluator.evaluate('abc'), null);
      });

      test('returns null for division by zero', () {
        expect(evaluator.evaluate('10/0'), null);
        expect(evaluator.evaluate('5+10/0'), null);
      });

      test('handles single number', () {
        expect(evaluator.evaluate('10'), 10.0);
        expect(evaluator.evaluate('10.5'), 10.5);
        expect(evaluator.evaluate('-10'), -10.0);
      });

      test('handles whitespace', () {
        expect(evaluator.evaluate('10 + 5'), 15.0);
        expect(evaluator.evaluate(' 10 + 5 '), 15.0);
        expect(evaluator.evaluate('10+ 5*2'), 20.0);
      });
    });

    group('Edge cases', () {
      test('very large numbers', () {
        expect(evaluator.evaluate('1000000+2000000'), 3000000.0);
      });

      test('very small decimal numbers', () {
        expect(evaluator.evaluate('0.001+0.002'), closeTo(0.003, 0.0000001));
      });

      test('zero operations', () {
        expect(evaluator.evaluate('0+0'), 0.0);
        expect(evaluator.evaluate('0*5'), 0.0);
        expect(evaluator.evaluate('5*0'), 0.0);
      });

      test('chained operations', () {
        expect(evaluator.evaluate('1+2+3+4+5'), 15.0);
        expect(evaluator.evaluate('2*3*4'), 24.0);
        expect(evaluator.evaluate('100/10/2'), 5.0);
      });
    });
  });
}
