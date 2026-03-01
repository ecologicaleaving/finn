# Fin - Family Expense Tracker

AI-powered family budget management app built with Flutter.

## Features

- 📊 **Expense Tracking**: Track personal and group expenses
- 💰 **Budget Management**: Set and monitor category budgets
- 🤖 **AI Receipt Scanning**: Automatic expense entry from receipts
- 📱 **Real-time Sync**: Instant updates across all family members
- 🎨 **Custom Category Icons**: Visual icons with bilingual search (Italian/English)
- 📈 **Dashboard Analytics**: View spending trends and category breakdowns
- 🔄 **Recurring Expenses**: Automatic tracking of regular bills

## Build Configuration

### Icon Support

**CRITICAL**: All builds MUST include the `--no-tree-shake-icons` flag to preserve Material Icons used by the icon picker:

```bash
# Development builds
flutter run --flavor dev --no-tree-shake-icons

# Production builds
flutter build apk --flavor prod --release --no-tree-shake-icons
```

This flag prevents Flutter from removing "unused" Material Icons during tree-shaking, ensuring all icons are available in the icon picker.

### Build Scripts

The following scripts automatically include the required flag:
- `build_and_install.ps1` - Windows development build and install
- `build_dev.sh` - Cross-platform development build

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
