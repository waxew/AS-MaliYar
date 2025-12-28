import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:waterflyiii/utils/math_expression_evaluator.dart';

/// Number Input Widget with Math Evaluation Support
///
/// A text input field for numeric values that supports:
/// - Basic number input with decimal support
/// - Mathematical operations (+, -, *, /) with automatic evaluation
/// - Chained calculations (evaluates when a second operator is pressed)
/// - Evaluation on Enter key press
/// - Evaluation on focus loss
///
/// Example:
/// ```dart
/// NumberInput(
///   controller: amountController,
///   focusNode: amountFocusNode,
///   decimals: 2,
///   onChanged: (value) => amount = double.tryParse(value) ?? 0,
/// )
/// ```
class NumberInput extends StatefulWidget {
  const NumberInput({
    super.key,
    this.label,
    this.controller,
    this.value,
    this.onChanged,
    this.error,
    this.icon,
    this.hintText,
    this.prefixText,
    this.decimals = 0,
    this.disabled = false,
    this.style,
    this.focusNode,
    this.enableMathEvaluation = true,
  });

  final TextEditingController? controller;
  final String? value;
  final String? label;
  final Function? onChanged;
  final String? error;
  final Widget? icon;
  final String? hintText;
  final String? prefixText;
  final int decimals;
  final bool disabled;
  final TextStyle? style;
  final FocusNode? focusNode;
  final bool enableMathEvaluation;

  @override
  State<NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<NumberInput> {
  final Logger _log = Logger('NumberInput');
  final MathExpressionEvaluator _evaluator = MathExpressionEvaluator();
  String _previousText = '';

  @override
  void initState() {
    super.initState();
    _previousText = widget.controller?.text ?? widget.value ?? '';

    // Listen to focus changes for evaluation on focus loss
    if (widget.focusNode != null && widget.enableMathEvaluation) {
      widget.focusNode!.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    if (widget.focusNode != null && widget.enableMathEvaluation) {
      widget.focusNode!.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode != null &&
        !widget.focusNode!.hasFocus &&
        widget.controller != null) {
      // Format number or evaluate expression on focus loss
      _formatOrEvaluate(widget.controller!.text);
    }
  }

  void _evaluateExpression(String text, {required bool isFullEvaluation}) {
    if (text.isEmpty) {
      return;
    }

    _log.fine(() => 'Evaluating expression: $text (full: $isFullEvaluation)');

    try {
      double? result;
      if (isFullEvaluation) {
        result = _evaluator.evaluate(text);
      } else {
        // Partial evaluation for chained calculations
        result = _evaluator.evaluatePartial(text);
      }

      if (result != null && widget.controller != null) {
        final String formattedResult = _formatResult(result);
        widget.controller!.text = formattedResult;
        widget.controller!.selection = TextSelection.fromPosition(
          TextPosition(offset: formattedResult.length),
        );

        // Trigger onChanged with the evaluated result
        widget.onChanged?.call(formattedResult);

        _log.fine(() => 'Expression evaluated: $text -> $formattedResult');
      }
    } catch (e, stackTrace) {
      _log.warning('Error evaluating expression: $text', e, stackTrace);
    }
  }

  String _formatResult(double result, {bool removeTrailingZeros = false}) {
    if (widget.decimals > 0) {
      String formatted = result.toStringAsFixed(widget.decimals);
      if (removeTrailingZeros) {
        // Remove trailing zeros
        formatted = formatted.replaceAll(RegExp(r'0+$'), '');
        // Remove decimal point if no digits remain after it
        formatted = formatted.replaceAll(RegExp(r'\.$'), '');
      }
      return formatted;
    }
    return result.toStringAsFixed(0);
  }

  void _formatOrEvaluate(String text) {
    if (text.isEmpty) {
      return;
    }

    // Clean up invalid input (e.g., "10.5.5" -> "10.5")
    String cleanedText = text;
    final int firstDotIndex = cleanedText.indexOf('.');
    if (firstDotIndex != -1) {
      final int secondDotIndex = cleanedText.indexOf('.', firstDotIndex + 1);
      if (secondDotIndex != -1) {
        // Multiple decimal points - keep only the first part
        cleanedText = cleanedText.substring(0, secondDotIndex);
      }
    }

    if (widget.enableMathEvaluation) {
      // Check if it's an expression (contains operators)
      if (RegExp(r'[+\-*/]').hasMatch(cleanedText)) {
        // Evaluate expression
        _evaluateExpression(cleanedText, isFullEvaluation: true);
        return;
      }
    }

    // Format plain number
    final double? number = double.tryParse(cleanedText);
    if (number != null && widget.controller != null) {
      final String formattedNumber = _formatResult(
        number,
        removeTrailingZeros: true,
      );
      if (formattedNumber != cleanedText) {
        widget.controller!.text = formattedNumber;
        widget.controller!.selection = TextSelection.fromPosition(
          TextPosition(offset: formattedNumber.length),
        );
        widget.onChanged?.call(formattedNumber);
        _previousText = formattedNumber;
      }
    }
  }

  bool _isOperator(String char) {
    return char == '+' || char == '-' || char == '*' || char == '/';
  }

  void _handleTextChange(String newText) {
    // Clean up invalid input (e.g., "10.5.5" -> "10.5")
    String cleanedText = newText;
    final int firstDotIndex = cleanedText.indexOf('.');
    if (firstDotIndex != -1) {
      final int secondDotIndex = cleanedText.indexOf('.', firstDotIndex + 1);
      if (secondDotIndex != -1) {
        // Multiple decimal points - keep only the first part
        cleanedText = cleanedText.substring(0, secondDotIndex);
        if (cleanedText != newText && widget.controller != null) {
          widget.controller!.text = cleanedText;
          widget.controller!.selection = TextSelection.fromPosition(
            TextPosition(offset: cleanedText.length),
          );
        }
      }
    }

    if (!widget.enableMathEvaluation) {
      // Format number if it's a valid number that needs formatting
      final double? number = double.tryParse(cleanedText);
      if (number != null && widget.controller != null) {
        final String formattedNumber = _formatResult(
          number,
          removeTrailingZeros: true,
        );
        if (formattedNumber != cleanedText) {
          widget.controller!.text = formattedNumber;
          widget.controller!.selection = TextSelection.fromPosition(
            TextPosition(offset: formattedNumber.length),
          );
          widget.onChanged?.call(formattedNumber);
          _previousText = formattedNumber;
          return;
        }
      }
      widget.onChanged?.call(cleanedText);
      _previousText = cleanedText;
      return;
    }

    // Check if an operator was just pressed (chained calculation)
    if (cleanedText.length > _previousText.length) {
      final String addedChar = cleanedText.substring(_previousText.length);
      if (addedChar.length == 1 && _isOperator(addedChar)) {
        // Operator was pressed - check if there's a previous operator
        final String textBeforeNewOperator = cleanedText.substring(
          0,
          cleanedText.length - 1,
        );
        if (textBeforeNewOperator.isNotEmpty &&
            RegExp(r'[+\-*/]').hasMatch(textBeforeNewOperator)) {
          // Previous operator exists - evaluate partial expression
          final double? partialResult = _evaluator.evaluatePartial(
            textBeforeNewOperator,
          );
          if (partialResult != null && widget.controller != null) {
            final String formattedResult = _formatResult(partialResult);
            final String newExpression = formattedResult + addedChar;

            // Update controller with result + new operator
            widget.controller!.text = newExpression;
            widget.controller!.selection = TextSelection.fromPosition(
              TextPosition(offset: newExpression.length),
            );

            // Trigger onChanged with the new expression
            widget.onChanged?.call(newExpression);

            _previousText = newExpression;
            _log.fine(
              () =>
                  'Chained calculation: $textBeforeNewOperator -> $formattedResult, added operator: $addedChar',
            );
            return;
          }
        }
      }
    }

    // Check if it's a plain number (no operators) that needs formatting
    if (!RegExp(r'[+\-*/]').hasMatch(cleanedText)) {
      final double? number = double.tryParse(cleanedText);
      if (number != null && widget.controller != null) {
        final String formattedNumber = _formatResult(
          number,
          removeTrailingZeros: true,
        );
        if (formattedNumber != cleanedText) {
          widget.controller!.text = formattedNumber;
          widget.controller!.selection = TextSelection.fromPosition(
            TextPosition(offset: formattedNumber.length),
          );
          widget.onChanged?.call(formattedNumber);
          _previousText = formattedNumber;
          return;
        }
      }
    }

    // Normal text change - update previous text and call onChanged
    _previousText = cleanedText;
    widget.onChanged?.call(cleanedText);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      initialValue: widget.value,
      onChanged: _handleTextChange,
      onEditingComplete: () {
        // Format number or evaluate expression on Enter key press
        if (widget.controller != null) {
          _formatOrEvaluate(widget.controller!.text);
        }
        // Move focus to next field
        widget.focusNode?.unfocus();
      },
      readOnly: widget.disabled,
      enabled: !widget.disabled,
      keyboardType: TextInputType.numberWithOptions(
        decimal: (widget.decimals > 0),
      ),
      inputFormatters: <TextInputFormatter>[
        TextInputFormatter.withFunction((
          TextEditingValue oldValue,
          TextEditingValue newValue,
        ) {
          // Replace comma with dot
          String normalized = newValue.text.replaceAll(',', '.');

          // Handle multiple decimal points - keep only the first one
          final int firstDotIndex = normalized.indexOf('.');
          int? newSelectionOffset;
          if (firstDotIndex != -1) {
            final int secondDotIndex = normalized.indexOf(
              '.',
              firstDotIndex + 1,
            );
            if (secondDotIndex != -1) {
              // Multiple decimal points - keep only the first part
              normalized = normalized.substring(0, secondDotIndex);
              // Adjust selection to be at the end of the cleaned text
              newSelectionOffset = normalized.length;
            }
          }

          // Prevent consecutive operators
          if (widget.enableMathEvaluation) {
            if (RegExp(r'[+\-*/]{2,}').hasMatch(normalized)) {
              return oldValue; // Reject consecutive operators
            }
          }

          // Update selection if text was modified
          if (newSelectionOffset != null) {
            return TextEditingValue(
              text: normalized,
              selection: TextSelection.collapsed(offset: newSelectionOffset),
            );
          }

          return newValue.copyWith(text: normalized);
        }),
        FilteringTextInputFormatter.allow(RegExp(_getRegexString())),
      ],
      decoration: InputDecoration(
        label: (widget.label != null) ? Text(widget.label!) : null,
        hintText: widget.hintText,
        errorText: widget.error,
        icon: widget.icon,
        border: const OutlineInputBorder(),
        prefixText: widget.prefixText,
        filled: widget.disabled,
      ),
      style:
          widget.disabled
              ? widget.style?.copyWith(color: Theme.of(context).disabledColor)
              : widget.style,
    );
  }

  String _getRegexString() {
    // Allow more decimal places during input (up to 10), formatting will handle the limit
    const int maxDecimalPlaces = 10;

    if (!widget.enableMathEvaluation) {
      // Original regex without operators
      return (widget.decimals > 0)
          ? r'^[0-9]+[,.]{0,1}[0-9]{0,' + maxDecimalPlaces.toString() + r'}'
          : r'[0-9]';
    }

    // Regex with operators support
    // Pattern: optional leading minus, number, then optional (operator + optional number)*
    // Allows trailing operators for partial input (e.g., "10+")
    if (widget.decimals > 0) {
      // Pattern: ^-?[0-9]+([,.]{0,1}[0-9]{0,N})?([+\-*/]([0-9]+([,.]{0,1}[0-9]{0,N})?)?)?)*$
      final String decimalPart =
          r'([,.]{0,1}[0-9]{0,' + maxDecimalPlaces.toString() + r'})';
      final String numberWithDecimal = r'([0-9]+' + decimalPart + r'?)';
      final String operatorWithNumber = r'([+\-*/]' + numberWithDecimal + r'?)';
      return r'^-?[0-9]+' + decimalPart + r'?(' + operatorWithNumber + r')*$';
    } else {
      // Pattern: ^-?[0-9]+([+\-*/]([0-9]+)?)?*$
      final String numberPart = r'([0-9]+)';
      final String operatorWithNumber = r'([+\-*/]' + numberPart + r'?)';
      return r'^-?[0-9]+(' + operatorWithNumber + r')*$';
    }
  }
}
