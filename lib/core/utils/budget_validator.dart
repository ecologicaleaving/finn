import '../../features/budgets/domain/entities/budget_composition_entity.dart';
import '../../features/budgets/domain/entities/budget_validation_issue_entity.dart';
import '../../features/budgets/domain/entities/category_budget_with_members_entity.dart';
import '../../features/budgets/domain/entities/member_contribution_entity.dart';
import 'currency_utils.dart';

/// Service for validating budget composition
///
/// Performs comprehensive validation checks including:
/// - Over-allocation detection (category budgets > group budget)
/// - Percentage overflow (member percentages > 100%)
/// - Invalid percentage values (outside 0-100 range)
/// - Invalid amounts (negative or too large; zero category budgets are allowed)
/// - Missing required budgets
class BudgetValidator {
  /// Maximum budget amount (€10,000,000 = 1 billion cents)
  static const int MAX_BUDGET_CENTS = 1000000000;

  /// Percentage near limit threshold (80%)
  static const double NEAR_LIMIT_THRESHOLD = 80.0;

  /// Validates a complete budget composition
  ///
  /// Returns a list of validation issues (errors and warnings).
  /// Empty list means validation passed.
  ///
  /// Example:
  /// ```dart
  /// final issues = BudgetValidator.validateComposition(composition);
  /// if (issues.any((issue) => issue.isError)) {
  ///   // Handle errors
  /// }
  /// ```
  static List<BudgetValidationIssue> validateComposition(
    BudgetComposition composition,
  ) {
    final issues = <BudgetValidationIssue>[];

    // Check 1: Validate group budget amount (if set)
    if (composition.hasGroupBudget) {
      final groupBudgetAmount = composition.groupBudgetAmount;

      if (groupBudgetAmount <= 0) {
        issues.add(BudgetValidationIssue.invalidAmount(
          context: 'Budget gruppo',
          amount: groupBudgetAmount,
        ));
      }

      if (groupBudgetAmount > MAX_BUDGET_CENTS) {
        issues.add(BudgetValidationIssue(
          type: IssueType.invalidAmount,
          severity: Severity.error,
          message:
              'Budget gruppo (${CurrencyUtils.formatCents(groupBudgetAmount)}) '
              'supera il limite massimo (${CurrencyUtils.formatCents(MAX_BUDGET_CENTS)})',
        ));
      }

      // Check 2: Sum of category budgets ≤ group budget (over-allocation)
      final totalCategoryBudgets = composition.stats.totalCategoryBudgets;

      if (totalCategoryBudgets > groupBudgetAmount) {
        issues.add(BudgetValidationIssue.overAllocation(
          categoryTotal: totalCategoryBudgets,
          groupBudget: groupBudgetAmount,
        ));
      }
    } else if (composition.hasCategoryBudgets) {
      // Warning: category budgets set but no group budget
      issues.add(BudgetValidationIssue.missingGroupBudget());
    }

    // Check 3: Validate each category budget
    for (final categoryBudget in composition.categoryBudgets) {
      issues.addAll(_validateCategoryBudget(categoryBudget));
    }

    return issues;
  }

  /// Validates a single category budget
  static List<BudgetValidationIssue> _validateCategoryBudget(
    CategoryBudgetWithMembers categoryBudget,
  ) {
    final issues = <BudgetValidationIssue>[];

    // Check category budget amount
    if (categoryBudget.groupBudgetAmount < 0) {
      issues.add(BudgetValidationIssue.invalidAmount(
        context: 'Budget categoria "${categoryBudget.categoryName}"',
        amount: categoryBudget.groupBudgetAmount,
      ));
      return issues; // Skip further checks if amount is invalid
    }

    // A zero budget is legitimate (e.g. the auto-created "Varie" catch-all
    // category): it is not a validation issue (issue #50).
    if (categoryBudget.groupBudgetAmount == 0) {
      return issues;
    }

    if (categoryBudget.groupBudgetAmount > MAX_BUDGET_CENTS) {
      issues.add(BudgetValidationIssue(
        type: IssueType.invalidAmount,
        severity: Severity.error,
        message:
            'Categoria "${categoryBudget.categoryName}": budget '
            '(${CurrencyUtils.formatCents(categoryBudget.groupBudgetAmount)}) '
            'supera il limite massimo',
        categoryId: categoryBudget.categoryId,
      ));
    }

    // Check member contributions
    if (categoryBudget.memberContributions.isNotEmpty) {
      // Separate percentage and fixed contributions
      final percentageContributions = categoryBudget.memberContributions
          .where((c) => c.isPercentage)
          .toList();
      final fixedContributions = categoryBudget.memberContributions
          .where((c) => c.isFixed)
          .toList();

      // Validate percentage contributions
      if (percentageContributions.isNotEmpty) {
        issues.addAll(_validatePercentageContributions(
          categoryBudget,
          percentageContributions,
        ));
      }

      // Validate fixed contributions
      if (fixedContributions.isNotEmpty) {
        issues.addAll(_validateFixedContributions(
          categoryBudget,
          fixedContributions,
        ));
      }

      // Check total member contributions vs category budget
      if (categoryBudget.isOverAllocated) {
        issues.add(BudgetValidationIssue(
          type: IssueType.overAllocation,
          severity: Severity.warning,
          message:
              'Categoria "${categoryBudget.categoryName}": contributi membri '
              '(${CurrencyUtils.formatCents(categoryBudget.totalMemberContributions)}) '
              'superano il budget categoria '
              '(${CurrencyUtils.formatCents(categoryBudget.groupBudgetAmount)})',
          categoryId: categoryBudget.categoryId,
        ));
      }
    }

    return issues;
  }

  /// Validates percentage-based member contributions
  static List<BudgetValidationIssue> _validatePercentageContributions(
    CategoryBudgetWithMembers categoryBudget,
    List<MemberContribution> percentageContributions,
  ) {
    final issues = <BudgetValidationIssue>[];

    // Check individual percentages are in valid range
    for (final contribution in percentageContributions) {
      final percentage = contribution.percentage!;

      if (percentage < 0 || percentage > 100) {
        issues.add(BudgetValidationIssue.invalidPercentage(
          userName: contribution.userName,
          categoryId: categoryBudget.categoryId,
          userId: contribution.userId,
          percentage: percentage,
        ));
      }
    }

    // Check sum of percentages ≤ 100%
    final totalPercentage = percentageContributions.fold<double>(
      0.0,
      (sum, c) => sum + c.percentage!,
    );

    if (totalPercentage > 100.0) {
      issues.add(BudgetValidationIssue.percentageOverflow(
        categoryName: categoryBudget.categoryName,
        categoryId: categoryBudget.categoryId,
        totalPercentage: totalPercentage,
      ));
    }

    return issues;
  }

  /// Validates fixed-amount member contributions
  static List<BudgetValidationIssue> _validateFixedContributions(
    CategoryBudgetWithMembers categoryBudget,
    List<MemberContribution> fixedContributions,
  ) {
    final issues = <BudgetValidationIssue>[];

    for (final contribution in fixedContributions) {
      final amount = contribution.fixedAmount!;

      // Check amount is positive
      if (amount <= 0) {
        issues.add(BudgetValidationIssue(
          type: IssueType.invalidAmount,
          severity: Severity.error,
          message:
              'Categoria "${categoryBudget.categoryName}", ${contribution.userName}: '
              'importo fisso non valido (${CurrencyUtils.formatCents(amount)})',
          categoryId: categoryBudget.categoryId,
          userId: contribution.userId,
        ));
      }

      // Check amount doesn't exceed category budget
      if (amount > categoryBudget.groupBudgetAmount) {
        issues.add(BudgetValidationIssue(
          type: IssueType.overAllocation,
          severity: Severity.warning,
          message:
              'Categoria "${categoryBudget.categoryName}", ${contribution.userName}: '
              'contributo fisso (${CurrencyUtils.formatCents(amount)}) '
              'supera budget categoria (${CurrencyUtils.formatCents(categoryBudget.groupBudgetAmount)})',
          categoryId: categoryBudget.categoryId,
          userId: contribution.userId,
        ));
      }

      // Check amount doesn't exceed max
      if (amount > MAX_BUDGET_CENTS) {
        issues.add(BudgetValidationIssue(
          type: IssueType.invalidAmount,
          severity: Severity.error,
          message:
              'Categoria "${categoryBudget.categoryName}", ${contribution.userName}: '
              'contributo fisso (${CurrencyUtils.formatCents(amount)}) '
              'supera il limite massimo',
          categoryId: categoryBudget.categoryId,
          userId: contribution.userId,
        ));
      }
    }

    return issues;
  }

  /// Quick validation check - returns true if composition has errors
  static bool hasErrors(BudgetComposition composition) {
    final issues = validateComposition(composition);
    return issues.any((issue) => issue.isError);
  }

  /// Quick validation check - returns true if composition has warnings
  static bool hasWarnings(BudgetComposition composition) {
    final issues = validateComposition(composition);
    return issues.any((issue) => issue.isWarning);
  }

  /// Checks if a single amount is valid
  static bool isValidAmount(int cents) {
    return CurrencyUtils.isValidCentsAmount(cents) && cents <= MAX_BUDGET_CENTS;
  }

  /// Checks if a percentage value is valid
  static bool isValidPercentage(double percentage) {
    return percentage >= 0.0 && percentage <= 100.0;
  }
}
