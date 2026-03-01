/// Enum representing the frequency of recurring expenses.
///
/// Used to determine how often a recurring expense should generate
/// new expense instances.
enum RecurrenceFrequency {
  /// Daily recurrence - creates an expense every day
  daily,

  /// Weekly recurrence - creates an expense every 7 days
  weekly,

  /// Monthly recurrence - creates an expense on the same day each month
  monthly,

  /// Yearly recurrence - creates an expense on the same date each year
  yearly;

  /// Returns a human-readable display string for the frequency
  String get displayString {
    switch (this) {
      case RecurrenceFrequency.daily:
        return 'Giornaliera';
      case RecurrenceFrequency.weekly:
        return 'Settimanale';
      case RecurrenceFrequency.monthly:
        return 'Mensile';
      case RecurrenceFrequency.yearly:
        return 'Annuale';
    }
  }

  /// Returns a short display string for the frequency
  String get shortDisplayString {
    switch (this) {
      case RecurrenceFrequency.daily:
        return 'Giorno';
      case RecurrenceFrequency.weekly:
        return 'Settimana';
      case RecurrenceFrequency.monthly:
        return 'Mese';
      case RecurrenceFrequency.yearly:
        return 'Anno';
    }
  }

  /// Converts a string value to RecurrenceFrequency enum
  static RecurrenceFrequency fromString(String value) {
    switch (value.toLowerCase()) {
      case 'daily':
        return RecurrenceFrequency.daily;
      case 'weekly':
        return RecurrenceFrequency.weekly;
      case 'monthly':
        return RecurrenceFrequency.monthly;
      case 'yearly':
        return RecurrenceFrequency.yearly;
      default:
        throw ArgumentError('Invalid recurrence frequency: $value');
    }
  }

  /// Converts the enum to a string value for storage
  String toStorageString() {
    return name;
  }
}
