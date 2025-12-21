import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:waterflyiii/services/math_expression_evaluator.dart';

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
  bool _isEvaluating = false;

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
        widget.enableMathEvaluation &&
        widget.controller != null) {
      // Evaluate on focus loss
      _evaluateExpression(widget.controller!.text, isFullEvaluation: true);
    }
  }

  void _evaluateExpression(String text, {required bool isFullEvaluation}) {
    if (_isEvaluating || text.isEmpty) {
      return;
    }

    _isEvaluating = true;
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
    } finally {
      _isEvaluating = false;
    }
  }

  String _formatResult(double result) {
    if (widget.decimals > 0) {
      return result.toStringAsFixed(widget.decimals);
    }
    return result.toStringAsFixed(0);
  }

  bool _isOperator(String char) {
    return char == '+' || char == '-' || char == '*' || char == '/';
  }

  void _handleTextChange(String newText) {
    if (!widget.enableMathEvaluation || _isEvaluating) {
      widget.onChanged?.call(newText);
      _previousText = newText;
      return;
    }

    // Check if an operator was just pressed (chained calculation)
    if (newText.length > _previousText.length) {
      final String addedChar = newText.substring(_previousText.length);
      if (addedChar.length == 1 && _isOperator(addedChar)) {
        // Operator was pressed - check if there's a previous operator
        final String textBeforeNewOperator = newText.substring(
          0,
          newText.length - 1,
        );
        if (textBeforeNewOperator.isNotEmpty &&
            RegExp(r'[+\-*/]').hasMatch(textBeforeNewOperator)) {
          // Previous operator exists - evaluate partial expression
          final double? partialResult = _evaluator.evaluatePartial(
            textBeforeNewOperator,
          );
          if (partialResult != null && widget.controller != null) {
            // Set evaluating flag to prevent recursive calls
            _isEvaluating = true;
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
            _isEvaluating = false;
            _log.fine(
              () =>
                  'Chained calculation: $textBeforeNewOperator -> $formattedResult, added operator: $addedChar',
            );
            return;
          }
        }
      }
    }

    // Normal text change - update previous text and call onChanged
    _previousText = newText;
    widget.onChanged?.call(newText);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      initialValue: widget.value,
      onChanged: _handleTextChange,
      onEditingComplete: () {
        // Evaluate on Enter key press
        if (widget.enableMathEvaluation && widget.controller != null) {
          _evaluateExpression(widget.controller!.text, isFullEvaluation: true);
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
        FilteringTextInputFormatter.allow(RegExp(_getRegexString())),
        TextInputFormatter.withFunction((
          TextEditingValue oldValue,
          TextEditingValue newValue,
        ) {
          // Replace comma with dot
          final String normalized = newValue.text.replaceAll(',', '.');

          // Prevent consecutive operators
          if (widget.enableMathEvaluation) {
            if (RegExp(r'[+\-*/]{2,}').hasMatch(normalized)) {
              return oldValue; // Reject consecutive operators
            }
          }

          return newValue.copyWith(text: normalized);
        }),
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
    if (!widget.enableMathEvaluation) {
      // Original regex without operators
      return (widget.decimals > 0)
          ? r'^[0-9]+[,.]{0,1}[0-9]{0,' + widget.decimals.toString() + r'}'
          : r'[0-9]';
    }

    // Regex with operators support
    // Pattern: optional leading minus, number, then optional (operator + optional number)*
    // Allows trailing operators for partial input (e.g., "10+")
    if (widget.decimals > 0) {
      // Pattern: ^-?[0-9]+([,.]{0,1}[0-9]{0,N})?([+\-*/]([0-9]+([,.]{0,1}[0-9]{0,N})?)?)?)*$
      final String decimalPart =
          r'([,.]{0,1}[0-9]{0,' + widget.decimals.toString() + r'})';
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
