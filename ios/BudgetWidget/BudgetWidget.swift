import WidgetKit
import SwiftUI

// Feature 001: Updated widget to display totalAmount + expenseCount
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(
            date: Date(),
            totalAmount: 342.50,
            expenseCount: 12,
            month: "Gennaio 2026",
            currency: "€",
            isDarkMode: false,
            hasError: false,
            lastUpdated: Date(),
            groupName: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> ()) {
        let entry = loadWidgetData() ?? placeholder(in: context)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        let entry = loadWidgetData() ?? placeholder(in: context)

        // Update every 15 minutes (Feature 001: Reduced from 30)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func loadWidgetData() -> BudgetEntry? {
        // Load data from App Group UserDefaults (Feature 001: Updated App Group ID)
        guard let userDefaults = UserDefaults(suiteName: "group.com.ecologicaleaving.fin") else {
            return nil
        }

        // Feature 001: Load new data format
        let totalAmount = userDefaults.double(forKey: "flutter.totalAmount")
        let expenseCount = userDefaults.integer(forKey: "flutter.expenseCount")
        let month = userDefaults.string(forKey: "flutter.month") ?? ""
        let currency = userDefaults.string(forKey: "flutter.currency") ?? "€"
        let isDarkMode = userDefaults.bool(forKey: "flutter.isDarkMode")
        let hasError = userDefaults.bool(forKey: "flutter.hasError")
        let lastUpdatedTimestamp = userDefaults.double(forKey: "flutter.lastUpdated")
        let groupName = userDefaults.string(forKey: "flutter.groupName")

        let lastUpdated = lastUpdatedTimestamp > 0
            ? Date(timeIntervalSince1970: lastUpdatedTimestamp / 1000.0)
            : Date()

        return BudgetEntry(
            date: Date(),
            totalAmount: totalAmount,
            expenseCount: expenseCount,
            month: month,
            currency: currency,
            isDarkMode: isDarkMode,
            hasError: hasError,
            lastUpdated: lastUpdated,
            groupName: groupName?.isEmpty == false ? groupName : nil
        )
    }
}

// Feature 001: Updated BudgetEntry with new fields
struct BudgetEntry: TimelineEntry {
    let date: Date
    let totalAmount: Double
    let expenseCount: Int
    let month: String
    let currency: String
    let isDarkMode: Bool
    let hasError: Bool
    let lastUpdated: Date
    let groupName: String?

    // Feature 001: New formatted display text
    var totalFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currency
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: NSNumber(value: totalAmount)) ?? "\(currency)0,00"
    }

    var countText: String {
        return expenseCount == 1 ? "1 spesa" : "\(expenseCount) spese"
    }

    var displayText: String {
        return "\(totalFormatted) • \(countText)"
    }

    // Feature 001: Staleness check (24 hours)
    var isStale: Bool {
        let diff = Date().timeIntervalSince(lastUpdated)
        return diff > (24 * 60 * 60) // 24 hours
    }

    var showError: Bool {
        return hasError || isStale
    }
}

struct BudgetWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry, colorScheme: colorScheme)
        case .systemMedium:
            MediumWidgetView(entry: entry, colorScheme: colorScheme)
        case .systemLarge:
            LargeWidgetView(entry: entry, colorScheme: colorScheme)
        @unknown default:
            MediumWidgetView(entry: entry, colorScheme: colorScheme)
        }
    }
}

struct SmallWidgetView: View {
    let entry: BudgetEntry
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.month)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(entry.spentFormatted) / \(entry.limitFormatted)")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("\(Int(entry.percentage))%")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ProgressView(value: entry.percentage, total: 100)
                .tint(entry.progressColor)
                .frame(height: 6)

            HStack(spacing: 8) {
                Link(destination: URL(string: "finapp://scan-receipt")!) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.blue)
                        .cornerRadius(8)
                }

                Link(destination: URL(string: "finapp://add-expense")!) {
                    Image(systemName: "plus")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(colorScheme == .dark ? .systemBackground : .white)
        }
    }
}

// Feature 001: Updated Medium Widget View
struct MediumWidgetView: View {
    let entry: BudgetEntry
    let colorScheme: ColorScheme

    // Feature 001: Flourishing Finances theme colors
    var deepForest: Color {
        Color(red: 0.24, green: 0.35, blue: 0.24) // #3D5A3C
    }

    var sageGreen: Color {
        Color(red: 0.48, green: 0.61, blue: 0.46) // #7A9B76
    }

    var cream: Color {
        Color(red: 1.0, green: 0.98, blue: 0.96) // #FFFBF5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Expense display (Feature 001: Updated format)
            Link(destination: URL(string: "finapp://dashboard")!) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.month)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(entry.totalFormatted)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(deepForest)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text(entry.countText)
                            .font(.body)
                            .foregroundColor(.secondary)

                        Spacer()

                        // Feature 001: Error indicator
                        if entry.showError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.body)
                                .foregroundColor(Color(red: 0.91, green: 0.55, blue: 0.48)) // softCoral
                        }
                    }
                }
            }

            // Quick actions
            HStack(spacing: 12) {
                Link(destination: URL(string: "finapp://scan-receipt")!) {
                    HStack {
                        Image(systemName: "doc.text.viewfinder")
                        Text("Scansiona")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(sageGreen)
                    .cornerRadius(8)
                }

                Link(destination: URL(string: "finapp://add-expense")!) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Manuale")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(sageGreen)
                    .cornerRadius(8)
                }
            }

            // Last updated
            HStack {
                Spacer()
                Text(formatLastUpdated(entry.lastUpdated))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            colorScheme == .dark ? Color(.systemBackground) : cream
        }
    }
}

struct LargeWidgetView: View {
    let entry: BudgetEntry
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Budget display
            Link(destination: URL(string: "finapp://dashboard")!) {
                VStack(alignment: .leading, spacing: 8) {
                    if let groupName = entry.groupName {
                        Text(groupName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(entry.month)
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.spentFormatted)
                            .font(.largeTitle)
                            .fontWeight(.semibold)

                        Text("/")
                            .font(.title)
                            .foregroundColor(.secondary)

                        Text(entry.limitFormatted)
                            .font(.title)
                            .foregroundColor(.secondary)
                    }

                    Text("\(Int(entry.percentage))% utilizzato")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)

                    ProgressView(value: entry.percentage, total: 100)
                        .tint(entry.progressColor)
                        .frame(height: 10)
                        .padding(.top, 4)
                }
            }

            // Quick actions
            HStack(spacing: 12) {
                Link(destination: URL(string: "finapp://scan-receipt")!) {
                    HStack {
                        Image(systemName: "doc.text.viewfinder")
                        Text("Scansiona Scontrino")
                            .fontWeight(.medium)
                    }
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(10)
                }

                Link(destination: URL(string: "finapp://add-expense")!) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Aggiungi Manuale")
                            .fontWeight(.medium)
                    }
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
            }

            // Last updated
            HStack {
                Spacer()
                Text(formatLastUpdated(entry.lastUpdated))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(colorScheme == .dark ? .systemBackground : .white)
        }
    }
}

private func formatLastUpdated(_ date: Date) -> String {
    let now = Date()
    let diff = now.timeIntervalSince(date)
    let minutes = Int(diff / 60)
    let hours = minutes / 60

    if minutes < 1 {
        return "Aggiornato ora"
    } else if minutes < 60 {
        return "Aggiornato \(minutes) min fa"
    } else if hours < 24 {
        return "Aggiornato \(hours) ore fa"
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        formatter.locale = Locale(identifier: "it_IT")
        return "Agg. \(formatter.string(from: date))"
    }
}

@main
struct BudgetWidget: Widget {
    let kind: String = "BudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BudgetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Budget Mensile")
        .description("Visualizza il budget mensile e aggiungi spese rapidamente")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// Feature 001: Updated preview with new data format
#Preview(as: .systemMedium) {
    BudgetWidget()
} timeline: {
    BudgetEntry(
        date: Date(),
        totalAmount: 342.50,
        expenseCount: 12,
        month: "Gennaio 2026",
        currency: "€",
        isDarkMode: false,
        hasError: false,
        lastUpdated: Date(),
        groupName: "Famiglia"
    )
}
