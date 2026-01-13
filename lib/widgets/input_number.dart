import 'package:decimal/decimal.dart';
import 'package:expressions/expressions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NumberInput extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (bool hasFocus) {
        if (hasFocus || controller == null) {
          return;
        }
        final String result = _evaluateExpression(controller!.text, decimals);
        controller!.text = result;
      },
      child: TextFormField(
        controller: controller,
        initialValue: value,
        onChanged: onChanged as void Function(String)?,
        readOnly: disabled,
        enabled: !disabled,
        keyboardType: TextInputType.numberWithOptions(decimal: (decimals > 0)),
        inputFormatters: <TextInputFormatter>[
          TextInputFormatter.withFunction(
            (TextEditingValue oldValue, TextEditingValue newValue) =>
                newValue.copyWith(text: newValue.text.replaceAll(',', '.')),
          ),
          TextInputFormatter.withFunction((
            TextEditingValue oldValue,
            TextEditingValue newValue,
          ) {
            if (newValue.composing != TextRange.empty) {
              return newValue;
            }

            // Check for operators in newValue
            final int opCount =
                RegExp(r'[+\-*/]').allMatches(newValue.text).length;

            // no operators --> normal number validation
            if (opCount == 0) {
              if (newValue.text.isNotEmpty &&
                  !_getRegex().hasMatch(newValue.text)) {
                return oldValue;
              }

              return newValue;
            }

            if (opCount > 1) {
              // Only when last operator was inserted at end
              if (newValue.text.startsWith(oldValue.text)) {
                final String result =
                    _evaluateExpression(oldValue.text, decimals);

                final String newText =
                    result + newValue.text.substring(oldValue.text.length);
                return newValue.copyWith(
                  text: newText,
                  selection: TextSelection.collapsed(offset: newText.length),
                );
              }
            }

            // Split number by operators, validate each number separately
            final List<String> numbers = newValue.text.split(
              RegExp(r'[+\-*/]'),
            );
            for (int i = 0; i < numbers.length; i++) {
              // As calculations like "0.005 * 1234" should be allowed, just check
              // if it's a valid number, regardless of decimals
              if (numbers[i].isNotEmpty &&
                  !RegExp(r'^[0-9]+[,.]?[0-9]*$').hasMatch(numbers[i])) {
                return oldValue;
              }
            }

            return newValue;
          }),
        ],
        decoration: InputDecoration(
          label: (label != null) ? Text(label!) : null,
          hintText: hintText,
          errorText: error,
          icon: icon,
          border: const OutlineInputBorder(),
          prefixText: prefixText,
          filled: disabled,
        ),
        style:
            disabled
                ? style?.copyWith(color: Theme.of(context).disabledColor)
                : style,
      ),
    );
  }

  RegExp _getRegex() =>
      (decimals > 0)
          ? RegExp(r'^[0-9]+[,.]{0,1}[0-9]{0,' + decimals.toString() + r'}$')
          : RegExp(r'^[0-9]+$');

  /// Evaluates a math expression and returns the result as a formatted string.
  /// Uses Decimal for proper rounding (avoids floating-point precision issues).
  String _evaluateExpression(String expression, int decimalPlaces) {
    final Expression? exp = Expression.tryParse(expression);
    if (exp == null) {
      return Decimal.zero.toStringAsFixed(decimalPlaces);
    }
    final dynamic result = const ExpressionEvaluator().eval(
      exp,
      <String, dynamic>{},
    );
    if (result == null) {
      return Decimal.zero.toStringAsFixed(decimalPlaces);
    }
    return Decimal.parse(result.toString()).toStringAsFixed(decimalPlaces);
  }
}
