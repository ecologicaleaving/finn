import 'package:flutter/material.dart';

import '../../../../../features/groups/domain/entities/member_entity.dart';

/// Widget for selecting who should reimburse an expense (Issue #19).
///
/// Shows an autocomplete field with family members + free text input,
/// optional partial amount, and optional note.
/// Only shown when reimbursement status is `reimbursable`.
class ReimbursementCreditorField extends StatefulWidget {
  const ReimbursementCreditorField({
    super.key,
    required this.familyMembers,
    required this.currentUserId,
    this.selectedLabel,
    this.selectedUserId,
    this.partialAmount,
    this.note,
    required this.onLabelChanged,
    required this.onUserIdChanged,
    this.onPartialAmountChanged,
    this.onNoteChanged,
    this.enabled = true,
  });

  /// Family members for autocomplete suggestions
  final List<MemberEntity> familyMembers;

  /// Current user ID (excluded from suggestions — can't reimburse yourself)
  final String currentUserId;

  /// Currently selected label (free text or member name)
  final String? selectedLabel;

  /// Currently selected user ID (null for external creditors)
  final String? selectedUserId;

  /// Optional partial reimbursement amount (null = full expense amount)
  final double? partialAmount;

  /// Optional note
  final String? note;

  /// Called when label changes
  final ValueChanged<String?> onLabelChanged;

  /// Called when user ID changes
  final ValueChanged<String?> onUserIdChanged;

  /// Called when partial amount changes
  final ValueChanged<double?>? onPartialAmountChanged;

  /// Called when note changes
  final ValueChanged<String?>? onNoteChanged;

  /// Whether the field is interactive
  final bool enabled;

  @override
  State<ReimbursementCreditorField> createState() =>
      _ReimbursementCreditorFieldState();
}

class _ReimbursementCreditorFieldState
    extends State<ReimbursementCreditorField> {
  late final TextEditingController _labelController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  bool _showExtraFields = false;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.selectedLabel ?? '');
    _amountController = TextEditingController(
      text: widget.partialAmount != null
          ? widget.partialAmount!.toStringAsFixed(2)
          : '',
    );
    _noteController =
        TextEditingController(text: widget.note ?? '');
    _showExtraFields =
        widget.partialAmount != null || (widget.note?.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<MemberEntity> get _otherMembers => widget.familyMembers
      .where((m) => m.userId != widget.currentUserId)
      .toList();

  void _selectMember(MemberEntity member) {
    _labelController.text = member.displayName;
    widget.onLabelChanged(member.displayName);
    widget.onUserIdChanged(member.userId);
  }

  void _clearCreditor() {
    _labelController.clear();
    widget.onLabelChanged(null);
    widget.onUserIdChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Da rimborsare a" label
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Da rimborsare a',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // Family member chips (quick select)
        if (_otherMembers.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _otherMembers.map((member) {
              final isSelected = widget.selectedUserId == member.userId;
              return FilterChip(
                label: Text(member.displayName),
                selected: isSelected,
                onSelected: widget.enabled
                    ? (_) => isSelected
                        ? _clearCreditor()
                        : _selectMember(member)
                    : null,
                selectedColor: colorScheme.primaryContainer,
                checkmarkColor: colorScheme.primary,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // Free text input (for external creditors like "Lavoro")
        TextField(
          controller: _labelController,
          enabled: widget.enabled,
          decoration: InputDecoration(
            hintText: 'Es. Lavoro, Amici...',
            prefixIcon: const Icon(Icons.person_outline),
            suffixIcon: _labelController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: widget.enabled ? _clearCreditor : null,
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onChanged: (value) {
            // If user types manually, clear the user ID (external creditor)
            if (widget.selectedUserId != null &&
                value !=
                    _otherMembers
                        .firstWhere(
                          (m) => m.userId == widget.selectedUserId,
                          orElse: () => MemberEntity(
                            userId: '',
                            groupId: '',
                            displayName: '',
                            email: '',
                            role: MemberRole.member,
                          ),
                        )
                        .displayName) {
              widget.onUserIdChanged(null);
            }
            widget.onLabelChanged(value.trim().isEmpty ? null : value.trim());
          },
        ),

        // Toggle for extra fields
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: widget.enabled
              ? () => setState(() => _showExtraFields = !_showExtraFields)
              : null,
          icon: Icon(
            _showExtraFields ? Icons.expand_less : Icons.expand_more,
            size: 18,
          ),
          label: Text(
            _showExtraFields
                ? 'Nascondi importo e nota'
                : 'Aggiungi importo parziale o nota',
            style: theme.textTheme.bodySmall,
          ),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),

        // Optional partial amount + note
        if (_showExtraFields) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            enabled: widget.enabled,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Importo parziale (opzionale)',
              prefixText: '€ ',
              hintText: 'Lascia vuoto per importo intero',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              final parsed = double.tryParse(value.replaceAll(',', '.'));
              widget.onPartialAmountChanged?.call(parsed);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: 'Nota rimborso (opzionale)',
              prefixIcon: const Icon(Icons.notes_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              widget.onNoteChanged
                  ?.call(value.trim().isEmpty ? null : value.trim());
            },
          ),
        ],
      ],
    );
  }
}
