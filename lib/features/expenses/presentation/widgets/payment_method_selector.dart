import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../payment_methods/presentation/providers/payment_method_provider.dart';

/// Widget for selecting a payment method in expense forms.
///
/// Displays a dropdown with default payment methods followed by custom methods.
/// Default payment methods are shown first, then custom methods are grouped separately.
class PaymentMethodSelector extends ConsumerStatefulWidget {
  const PaymentMethodSelector({
    super.key,
    required this.userId,
    this.selectedId,
    required this.onChanged,
    this.enabled = true,
  });

  final String userId;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  ConsumerState<PaymentMethodSelector> createState() => _PaymentMethodSelectorState();
}

class _PaymentMethodSelectorState extends ConsumerState<PaymentMethodSelector> {
  bool _hasNotifiedAutoSelection = false;

  @override
  Widget build(BuildContext context) {
    final paymentMethodState = ref.watch(paymentMethodProvider(widget.userId));

    // Show loading indicator while fetching
    if (paymentMethodState.isLoading && paymentMethodState.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Show error if failed to load
    if (paymentMethodState.hasError) {
      return ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: const Text('Errore nel caricamento'),
        subtitle: Text(paymentMethodState.errorMessage ?? 'Errore sconosciuto'),
      );
    }

    // Get default and custom methods
    final defaultMethods = paymentMethodState.defaultMethods;
    final customMethods = paymentMethodState.customMethods;

    // T011: Defensive edge case - no payment methods available
    if (defaultMethods.isEmpty && customMethods.isEmpty) {
      return ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: const Text('Nessun metodo di pagamento disponibile'),
        subtitle: const Text('Contatta l\'amministratore del gruppo'),
      );
    }

    // Build dropdown items
    final items = <DropdownMenuItem<String>>[];

    // Add default methods
    for (final method in defaultMethods) {
      items.add(
        DropdownMenuItem<String>(
          value: method.id,
          child: Row(
            children: [
              const Icon(Icons.payment, size: 20),
              const SizedBox(width: 8),
              Text(method.name),
            ],
          ),
        ),
      );
    }

    // Add separator if there are custom methods
    if (customMethods.isNotEmpty) {
      items.add(
        const DropdownMenuItem<String>(
          enabled: false,
          value: null,
          child: Divider(),
        ),
      );

      // Add custom methods
      for (final method in customMethods) {
        items.add(
          DropdownMenuItem<String>(
            value: method.id,
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet, size: 20),
                const SizedBox(width: 8),
                Text(method.name),
              ],
            ),
          ),
        );
      }
    }

    // T011: Determine selected value with defensive handling for deleted payment methods
    String? effectiveValue = widget.selectedId;

    // If widget.selectedId is not null, verify it still exists in available methods
    if (widget.selectedId != null) {
      final selectedExists = paymentMethodState.paymentMethods.any((m) => m.id == widget.selectedId);
      if (!selectedExists) {
        // Selected payment method was deleted - auto-select first available
        effectiveValue = defaultMethods.isNotEmpty
            ? defaultMethods.first.id
            : (customMethods.isNotEmpty ? customMethods.first.id : null);
      }
    } else {
      // No selection - default to Contanti or first available
      effectiveValue = paymentMethodState.defaultContanti?.id ??
          (defaultMethods.isNotEmpty
              ? defaultMethods.first.id
              : (customMethods.isNotEmpty ? customMethods.first.id : null));
    }

    // T010: Notify parent of auto-selection (fix for US1 bug)
    if (!_hasNotifiedAutoSelection && widget.selectedId == null && effectiveValue != null) {
      _hasNotifiedAutoSelection = true;
      // Capture value for closure
      final valueToNotify = effectiveValue;
      // Schedule callback after build completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onChanged(valueToNotify);
        }
      });
    }

    return DropdownButtonFormField<String>(
      value: effectiveValue,
      decoration: const InputDecoration(
        labelText: 'Metodo di Pagamento',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.payment),
      ),
      items: items,
      onChanged: widget.enabled ? widget.onChanged : null,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Seleziona un metodo di pagamento';
        }
        return null;
      },
    );
  }
}
