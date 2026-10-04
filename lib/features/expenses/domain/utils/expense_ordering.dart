import '../entities/expense_entity.dart';

/// Total order used everywhere an expense list is sorted (remote query,
/// repository merge, local cache, provider): newest first.
///
/// Criteria: `date` desc, then `createdAt` desc (null last, like PostgREST
/// `nullslast`), then `id` desc. The `id` makes the order deterministic, so
/// range/offset pagination never skips or repeats rows with equal dates.
int compareExpensesNewestFirst(ExpenseEntity a, ExpenseEntity b) {
  final byDate = b.date.compareTo(a.date);
  if (byDate != 0) return byDate;

  final aCreated = a.createdAt;
  final bCreated = b.createdAt;
  if (aCreated != null || bCreated != null) {
    if (aCreated == null) return 1;
    if (bCreated == null) return -1;
    final byCreated = bCreated.compareTo(aCreated);
    if (byCreated != 0) return byCreated;
  }

  return b.id.compareTo(a.id);
}
