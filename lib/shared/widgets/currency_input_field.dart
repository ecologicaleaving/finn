import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Reusable currency input field widget
///
/// Provides a text field for entering monetary amounts with:
/// - Automatic currency formatting
/// - Validation for non-negative amounts
/// - Support for cents/decimal input
/// - Clear visual feedback for validation errors
///
/// Used throughout budget setup and management screens
class CurrencyInputField extends StatefulWidget {
  /// Initial value in cents (smallest currency unit)
  final int? initialValue;

  /// Callback when value changes (returns amount in cents)
  final ValueChanged<int?>? onChanged;

  /// Callback when user completes input
  final ValueChanged<int?>? onSubmitted;

  /// Label text for the field
  final String? label;

  /// Hint text shown when field is empty
  final String? hint;

  /// Helper text shown below the field
  final String? helperText;

  /// Error text shown when validation fails
  final String? errorText;

  /// Whether the field is required
  final bool isRequired;

  /// Minimum allowed value in cents (default: 0)
  final int minValue;

  /// Maximum allowed value in cents (default: no limit)
  final int? maxValue;

  /// Whether to show decimal places (cents)
  final bool showDecimals;

  /// Currency symbol to display
  final String currencySymbol;

  /// Whether the field is enabled
  final bool enabled;

  /// Focus node for the field
  final FocusNode? focusNode;

  /// Text input action
  final TextInputAction? textInputAction;

  const CurrencyInputField({
    Key? key,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.isRequired = false,
    this.minValue = 0,
    this.maxValue,
    this.showDecimals = true,
    this.currencySymbol = '€',
    this.enabled = true,
    this.focusNode,
    this.textInputAction,
  }) : super(key: key);

  @override
  State<CurrencyInputField> createState() => _CurrencyInputFieldState();
}

class _CurrencyInputFieldState extends State<CurrencyInputField> {
  late TextEditingController _controller;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue != null
          ? _formatCentsToDisplay(widget.initialValue!)
          : '',
    );
  }

  @override
  void didUpdateWidget(CurrencyInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      _controller.text = widget.initialValue != null
          ? _formatCentsToDisplay(widget.initialValue!)
          : '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Format cents to display string (e.g., 1250 -> "12.50")
  String _formatCentsToDisplay(int cents) {
    if (widget.showDecimals) {
      final amount = cents / 100;
      return amount.toStringAsFixed(2);
    } else {
      return (cents / 100).round().toString();
    }
  }

  /// Parse display string to cents (e.g., "12.50" or "12,50" -> 1250)
  int? _parseDisplayToCents(String text) {
    if (text.isEmpty) return null;

    try {
      final amount = double.parse(_normalizeDecimal(text));
      return (amount * 100).round();
    } catch (e) {
      return null;
    }
  }

  /// Validate the input value
  String? _validate(int? cents) {
    if (cents == null) {
      if (widget.isRequired) {
        return 'This field is required';
      }
      return null;
    }

    if (cents < widget.minValue) {
      return 'Amount must be at least ${_formatCentsToDisplay(widget.minValue)} ${widget.currencySymbol}';
    }

    if (widget.maxValue != null && cents > widget.maxValue!) {
      return 'Amount cannot exceed ${_formatCentsToDisplay(widget.maxValue!)} ${widget.currencySymbol}';
    }

    return null;
  }

  void _handleTextChanged(String text) {
    final cents = _parseDisplayToCents(text);
    final error = _validate(cents);

    setState(() {
      _validationError = error;
    });

    widget.onChanged?.call(cents);
  }

  void _handleSubmitted(String text) {
    final cents = _parseDisplayToCents(text);
    final error = _validate(cents);

    setState(() {
      _validationError = error;
    });

    if (error == null) {
      widget.onSubmitted?.call(cents);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      keyboardType: TextInputType.numberWithOptions(
        decimal: widget.showDecimals,
        signed: false,
      ),
      textInputAction: widget.textInputAction ?? TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          widget.showDecimals
              ? RegExp(r'^\d+[.,]?\d{0,2}')
              : RegExp(r'^\d+'),
        ),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helperText,
        errorText: widget.errorText ?? _validationError,
        prefixText: widget.currencySymbol,
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  _handleTextChanged('');
                },
              )
            : null,
        border: const OutlineInputBorder(),
      ),
      onChanged: _handleTextChanged,
      onSubmitted: _handleSubmitted,
    );
  }
}

/// Extension for converting between cents and display formats
extension CurrencyFormatting on int {
  /// Format cents as currency string (e.g., 1250 -> "€12.50")
  String toCurrencyString({String symbol = '€', bool showDecimals = true}) {
    if (showDecimals) {
      final amount = this / 100;
      return '$symbol${amount.toStringAsFixed(2)}';
    } else {
      final amount = (this / 100).round();
      return '$symbol$amount';
    }
  }

  /// Format cents with locale-aware formatting
  String toLocaleCurrency({String locale = 'en_US', String symbol = 'EUR'}) {
    final formatter = NumberFormat.currency(
      locale: locale,
      symbol: symbol,
      decimalDigits: 2,
    );
    return formatter.format(this / 100);
  }
}

/// Helper function to parse currency string to cents
///
/// Accepts both '.' and ',' as decimal separator (e.g. "12,50" -> 1250,
/// "1,234.56" -> 123456, "1.234,56" -> 123456).
int? parseCurrencyToCents(String text) {
  try {
    final amount = double.parse(_normalizeDecimal(text));
    return (amount * 100).round();
  } catch (e) {
    return null;
  }
}

/// Normalizes a user-entered amount so it can be parsed by [double.parse].
///
/// Strips currency symbols and whitespace. When both '.' and ',' are present,
/// the last one is the decimal separator and the others are thousands
/// separators. When only ',' is present it is treated as decimal separator.
String _normalizeDecimal(String text) {
  var normalized = text.replaceAll(RegExp(r'[€$£¥\s]'), '');

  final lastDot = normalized.lastIndexOf('.');
  final lastComma = normalized.lastIndexOf(',');

  if (lastDot >= 0 && lastComma >= 0) {
    final decimalIndex = lastDot > lastComma ? lastDot : lastComma;
    final integerPart =
        normalized.substring(0, decimalIndex).replaceAll(RegExp(r'[.,]'), '');
    final fractionalPart = normalized.substring(decimalIndex + 1);
    normalized = '$integerPart.$fractionalPart';
  } else if (lastComma >= 0) {
    normalized = normalized.replaceAll(',', '.');
  }

  return normalized;
}
