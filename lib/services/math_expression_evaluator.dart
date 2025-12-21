import 'package:logging/logging.dart';

/// Math Expression Evaluator Service
///
/// Provides safe evaluation of mathematical expressions with support for:
/// - Basic arithmetic operations (+, -, *, /)
/// - Operator precedence (multiplication/division before addition/subtraction)
/// - Decimal numbers
/// - Partial expression evaluation for chained calculations
///
/// Example:
/// ```dart
/// final evaluator = MathExpressionEvaluator();
/// final result = evaluator.evaluate('10+5*2'); // Returns 20.0
/// final partial = evaluator.evaluatePartial('10+5*'); // Returns 15.0
/// ```
class MathExpressionEvaluator {
  MathExpressionEvaluator() : _log = Logger('MathExpressionEvaluator');

  final Logger _log;

  /// Evaluates a complete mathematical expression.
  ///
  /// Supports operators: +, -, *, /
  /// Handles operator precedence correctly.
  ///
  /// Parameters:
  /// - [expression]: The mathematical expression to evaluate
  ///
  /// Returns:
  /// - [double?] The evaluation result, or null if expression is invalid
  ///
  /// Throws:
  /// - No exceptions thrown, returns null for invalid expressions
  double? evaluate(String expression) {
    if (expression.isEmpty) {
      _log.fine('Empty expression provided');
      return null;
    }

    _log.fine(() => 'Evaluating expression: $expression');

    try {
      // Normalize expression: remove whitespace, replace comma with dot
      final String normalized = expression
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll(',', '.');

      // Validate expression format
      if (!isValidExpression(normalized)) {
        _log.warning('Invalid expression format: $normalized');
        return null;
      }

      // Parse and evaluate
      final double result = _evaluateExpression(normalized);
      _log.fine(() => 'Evaluation result: $result');
      return result;
    } catch (e, stackTrace) {
      _log.severe('Error evaluating expression: $expression', e, stackTrace);
      return null;
    }
  }

  /// Evaluates a partial expression up to the last operator.
  ///
  /// Used for chained calculations when a second operator is pressed.
  /// For example, "10+5*" would evaluate to 15.0 (evaluates "10+5").
  ///
  /// Parameters:
  /// - [expression]: The partial expression ending with an operator
  ///
  /// Returns:
  /// - [double?] The evaluation result, or null if expression is invalid
  double? evaluatePartial(String expression) {
    if (expression.isEmpty) {
      _log.fine('Empty partial expression provided');
      return null;
    }

    _log.fine(() => 'Evaluating partial expression: $expression');

    try {
      // Normalize expression
      final String normalized = expression
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll(',', '.');

      // Remove trailing operator for evaluation
      final String withoutTrailingOperator = normalized.replaceAll(
        RegExp(r'[+\-*/]$'),
        '',
      );

      if (withoutTrailingOperator.isEmpty) {
        _log.fine('Expression contains only operator');
        return null;
      }

      // Validate partial expression
      if (!isValidExpression(withoutTrailingOperator)) {
        _log.warning(
          'Invalid partial expression format: $withoutTrailingOperator',
        );
        return null;
      }

      // Evaluate without the trailing operator
      final double result = _evaluateExpression(withoutTrailingOperator);
      _log.fine(() => 'Partial evaluation result: $result');
      return result;
    } catch (e, stackTrace) {
      _log.severe(
        'Error evaluating partial expression: $expression',
        e,
        stackTrace,
      );
      return null;
    }
  }

  /// Validates if an expression has valid format.
  ///
  /// Checks for:
  /// - Valid number format
  /// - Valid operator placement
  /// - No consecutive operators
  /// - Proper decimal point usage
  ///
  /// Parameters:
  /// - [expression]: The expression to validate
  ///
  /// Returns:
  /// - [bool] True if expression format is valid, false otherwise
  bool isValidExpression(String expression) {
    if (expression.isEmpty) {
      return false;
    }

    // Remove whitespace and normalize
    final String normalized = expression
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(',', '.');

    // Check for empty after normalization
    if (normalized.isEmpty) {
      return false;
    }

    // Pattern: optional leading minus, number, then optional (operator + number)*
    // Allow: "123", "-123", "123+456", "123.45*67.89", etc.
    // Disallow: "++", "123++", "123.", ".123", etc.
    final RegExp validPattern = RegExp(r'^-?\d+(\.\d+)?([+\-*/]\d+(\.\d+)?)*$');

    if (!validPattern.hasMatch(normalized)) {
      return false;
    }

    // Additional checks: no consecutive operators, no trailing operators
    // (trailing operators are handled separately for partial evaluation)
    if (RegExp(r'[+\-*/]{2,}').hasMatch(normalized)) {
      return false;
    }

    // Check for division by zero (basic check)
    if (normalized.contains('/0') && !normalized.contains('/0.')) {
      // Allow /0.5, /0.123, etc., but not /0
      final RegExp divisionByZeroPattern = RegExp(r'/0(?!\.)');
      if (divisionByZeroPattern.hasMatch(normalized)) {
        _log.warning('Division by zero detected in expression: $normalized');
        return false;
      }
    }

    return true;
  }

  /// Internal method to evaluate a normalized expression.
  ///
  /// Uses operator precedence: multiplication/division before addition/subtraction.
  ///
  /// Parameters:
  /// - [expression]: Normalized expression (no whitespace, dots for decimals)
  ///
  /// Returns:
  /// - [double] The evaluation result
  ///
  /// Throws:
  /// - [FormatException] if expression cannot be parsed
  /// - [Exception] for division by zero or other errors
  double _evaluateExpression(String expression) {
    // Handle simple number (no operators)
    if (!RegExp(r'[+\-*/]').hasMatch(expression)) {
      final double? value = double.tryParse(expression);
      if (value == null) {
        throw FormatException('Invalid number: $expression');
      }
      return value;
    }

    // Split by operators while preserving them
    // Use a more sophisticated parsing approach
    final List<String> tokens = _tokenize(expression);
    if (tokens.isEmpty) {
      throw const FormatException('Empty expression after tokenization');
    }

    // Evaluate with operator precedence
    return _evaluateWithPrecedence(tokens);
  }

  /// Tokenizes an expression into numbers and operators.
  ///
  /// Parameters:
  /// - [expression]: Normalized expression
  ///
  /// Returns:
  /// - [List<String>] List of tokens (numbers and operators)
  List<String> _tokenize(String expression) {
    final List<String> tokens = <String>[];
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < expression.length; i++) {
      final String char = expression[i];

      if (char == '+' || char == '-' || char == '*' || char == '/') {
        // Save accumulated number
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        // Save operator
        tokens.add(char);
      } else {
        // Accumulate number characters
        buffer.write(char);
      }
    }

    // Add remaining number
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }

    return tokens;
  }

  /// Evaluates tokens with operator precedence.
  ///
  /// First processes multiplication and division, then addition and subtraction.
  ///
  /// Parameters:
  /// - [tokens]: List of tokens (numbers and operators)
  ///
  /// Returns:
  /// - [double] The evaluation result
  ///
  /// Throws:
  /// - [FormatException] for invalid tokens
  /// - [Exception] for division by zero
  double _evaluateWithPrecedence(List<String> tokens) {
    if (tokens.isEmpty) {
      throw const FormatException('Empty token list');
    }

    // Handle leading minus (negative first number)
    final String firstToken = tokens.first;
    if (firstToken == '-' && tokens.length > 1) {
      // Negative number at start
      final String secondToken = tokens[1];
      final double? firstNumber = double.tryParse(secondToken);
      if (firstNumber == null) {
        throw FormatException(
          'Invalid number after leading minus: $secondToken',
        );
      }
      tokens.removeRange(0, 2);
      tokens.insert(0, (-firstNumber).toString());
    }

    // First pass: handle multiplication and division
    final List<String> afterMulDiv = <String>[];
    for (int i = 0; i < tokens.length; i++) {
      if (i < tokens.length - 1 && (tokens[i] == '*' || tokens[i] == '/')) {
        // Get previous number and next number
        if (afterMulDiv.isEmpty) {
          throw FormatException('No left operand for operator ${tokens[i]}');
        }
        if (i + 1 >= tokens.length) {
          throw FormatException('No right operand for operator ${tokens[i]}');
        }

        final double? left = double.tryParse(afterMulDiv.removeLast());
        final String operator = tokens[i];
        final double? right = double.tryParse(tokens[i + 1]);

        if (left == null || right == null) {
          throw FormatException(
            'Invalid operands for $operator: ${tokens[i - 1]}, ${tokens[i + 1]}',
          );
        }

        double result;
        if (operator == '*') {
          result = left * right;
        } else if (operator == '/') {
          if (right == 0) {
            throw Exception('Division by zero');
          }
          result = left / right;
        } else {
          throw FormatException(
            'Unexpected operator in mul/div pass: $operator',
          );
        }

        afterMulDiv.add(result.toString());
        i++; // Skip the right operand as we've processed it
      } else if (tokens[i] != '*' && tokens[i] != '/') {
        // Not a mul/div operator, keep as is
        afterMulDiv.add(tokens[i]);
      }
    }

    // Second pass: handle addition and subtraction
    if (afterMulDiv.isEmpty) {
      throw const FormatException(
        'Empty expression after multiplication/division',
      );
    }

    double result = double.tryParse(afterMulDiv[0]) ?? 0.0;
    for (int i = 1; i < afterMulDiv.length; i += 2) {
      if (i + 1 >= afterMulDiv.length) {
        throw FormatException('Incomplete expression at index $i');
      }

      final String operator = afterMulDiv[i];
      final double? right = double.tryParse(afterMulDiv[i + 1]);

      if (right == null) {
        throw FormatException('Invalid right operand: ${afterMulDiv[i + 1]}');
      }

      if (operator == '+') {
        result += right;
      } else if (operator == '-') {
        result -= right;
      } else {
        throw FormatException('Unexpected operator in add/sub pass: $operator');
      }
    }

    return result;
  }
}
