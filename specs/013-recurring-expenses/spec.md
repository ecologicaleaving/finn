# Feature Specification: Recurring Expenses and Reimbursements Management

**Feature Branch**: `013-recurring-expenses`
**Created**: 2026-01-16
**Status**: Draft
**Input**: User description: "vorrei aggiungere all spese la possibilità di definirle "spese ricorrenti" , impostare una frequenza e "prenotarne il budget", poi, in settings aggiungi il menu "spese ricorrenti" per gestirle e "rimborsi" dove si vedono le spese marcate come da rimborsare o rimborsate"

## Clarifications

### Session 2026-01-16

- Q: When should the system automatically create expense instances from a recurring expense template? → A: Automatic - System creates the next occurrence when the recurrence period arrives (e.g., monthly expense creates new instance on the same day each month)
- Q: When a user first marks an expense as recurring, when should the first occurrence be scheduled? → A: Use the expense date - If converting an existing expense, use its original date as the recurrence anchor; if creating new, use the date field value
- Q: What should happen if the app is offline when a recurring expense is scheduled to be created? → A: Create locally immediately - Expense instance is created in local storage and synced when online (no delay)
- Q: When a user converts an existing expense to a recurring expense, what should happen to the original expense? → A: Convert to template - The original expense becomes the recurring template and remains visible with a recurring indicator; future occurrences are created as separate expenses
- Q: When a recurring expense is paused, how long can it remain paused before any automatic action is taken? → A: Indefinitely - Paused recurring expenses remain paused until the user manually resumes or deletes them, with no automatic archival

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Mark Expenses as Recurring (Priority: P1)

Users need to mark certain expenses as recurring with a specific frequency (e.g., monthly rent, weekly groceries, daily coffee). When creating or editing an expense, users can designate it as recurring and set the recurrence pattern.

**Why this priority**: This is the foundational capability that enables all other recurring expense functionality. Without the ability to mark and configure recurring expenses, no other features in this specification can work.

**Independent Test**: Can be fully tested by creating a new expense, marking it as recurring, setting a frequency (daily, weekly, monthly, yearly), and verifying the expense is saved with the recurring configuration. Delivers immediate value by capturing the recurring nature of expenses.

**Acceptance Scenarios**:

1. **Given** a user is creating a new expense, **When** they view the expense form, **Then** an option to mark the expense as "recurring" is available
2. **Given** a user marks an expense as recurring, **When** they select the recurring option, **Then** frequency options are displayed (daily, weekly, monthly, yearly)
3. **Given** a user selects a recurrence frequency, **When** they save the expense, **Then** the expense is saved with the recurring configuration
4. **Given** an existing non-recurring expense, **When** a user edits it and marks it as recurring, **Then** the expense is transformed into a recurring template that remains visible with a recurring indicator
5. **Given** an existing recurring expense, **When** a user views the expense details, **Then** the recurrence frequency is clearly displayed
6. **Given** a recurring expense template exists, **When** future occurrences are created, **Then** they appear as separate expense instances distinct from the template
7. **Given** a user is editing a recurring expense, **When** they change or remove the recurring configuration, **Then** the changes are saved and reflected in the expense details

---

### User Story 2 - Budget Reservation for Recurring Expenses (Priority: P2)

Users can "reserve" budget for recurring expenses, allowing them to see how much of their budget is committed to upcoming recurring payments. This helps with financial planning by showing available budget after accounting for known future expenses.

**Why this priority**: While valuable for budget planning, this feature depends on having recurring expenses configured first. It enhances the utility of recurring expenses but is not essential for basic functionality.

**Independent Test**: Can be fully tested by creating recurring expenses, reserving budget for them, and verifying that the budget overview shows both total budget and available budget after reservations.

**Acceptance Scenarios**:

1. **Given** a user has created a recurring expense, **When** they view the expense details, **Then** an option to "reserve budget" for this recurring expense is available
2. **Given** a user enables budget reservation for a recurring expense, **When** the budget is calculated, **Then** the reserved amount is deducted from available budget
3. **Given** multiple recurring expenses with budget reservations, **When** the user views the budget overview, **Then** a summary shows total reserved budget for all recurring expenses
4. **Given** a user views the budget dashboard, **When** budget reservations are active, **Then** the display shows both "total budget" and "available budget (after reservations)"
5. **Given** a recurring expense with budget reservation, **When** the recurrence period arrives and the expense is created, **Then** the reserved budget is adjusted accordingly
6. **Given** a user disables budget reservation for a recurring expense, **When** the budget is recalculated, **Then** the reserved amount is no longer deducted from available budget

---

### User Story 3 - Recurring Expenses Management Screen (Priority: P3)

Users can access a dedicated management screen in Settings to view, edit, and manage all their recurring expenses in one place. This provides a centralized location for overseeing all recurring financial commitments.

**Why this priority**: This is a convenience feature that improves usability but is not essential for core functionality. Users can still manage recurring expenses through the regular expense views, though less conveniently.

**Independent Test**: Can be fully tested by navigating to Settings > Recurring Expenses and verifying that all recurring expenses are listed with options to view, edit, pause, or delete them.

**Acceptance Scenarios**:

1. **Given** a user navigates to Settings, **When** they view the settings menu, **Then** a "Recurring Expenses" option is available
2. **Given** a user selects "Recurring Expenses" from settings, **When** the screen loads, **Then** all recurring expenses are displayed in a list with their frequency and amount
3. **Given** the recurring expenses management screen is displayed, **When** the user selects a recurring expense, **Then** they can view full details and edit the configuration
4. **Given** a user is viewing the recurring expenses list, **When** they want to temporarily pause a recurring expense, **Then** an option to pause/resume is available
5. **Given** a recurring expense is paused, **When** the recurrence period arrives, **Then** no new expense instance is automatically created
6. **Given** a user wants to delete a recurring expense, **When** they initiate deletion, **Then** a confirmation dialog asks if they want to delete future occurrences only or all historical occurrences as well

---

### User Story 4 - Reimbursements Management Screen (Priority: P3)

Users can access a dedicated screen in Settings to view and manage all expenses marked as reimbursable or reimbursed. This provides a centralized view of money owed to the budget and money already returned.

**Why this priority**: This feature leverages existing reimbursement functionality (Feature 012) and provides a convenient view, but doesn't add new core capabilities. It's a usability enhancement rather than essential functionality.

**Independent Test**: Can be fully tested by navigating to Settings > Reimbursements and verifying that all expenses with reimbursement status are displayed, filterable by status (reimbursable vs. reimbursed).

**Acceptance Scenarios**:

1. **Given** a user navigates to Settings, **When** they view the settings menu, **Then** a "Reimbursements" option is available
2. **Given** a user selects "Reimbursements" from settings, **When** the screen loads, **Then** all expenses marked as reimbursable or reimbursed are displayed
3. **Given** the reimbursements screen is displayed, **When** the user views the list, **Then** expenses are grouped or filterable by status (reimbursable, reimbursed)
4. **Given** the reimbursements screen shows the expense list, **When** the user views the screen, **Then** summary totals show: total pending reimbursements and total reimbursed amounts
5. **Given** a user selects a reimbursable expense from the list, **When** they view the details, **Then** they can mark it as reimbursed directly from this screen
6. **Given** the reimbursements list contains multiple expenses, **When** the user wants to find specific reimbursements, **Then** search and filter options are available

---

### Edge Cases

- What happens when a user deletes a recurring expense that has already generated multiple historical instances?
- How does the system handle budget reservations when the budget period changes (e.g., switching from monthly to yearly view)?
- What happens if a recurring expense frequency is changed after budget reservation is enabled?
- Paused recurring expenses remain paused indefinitely until the user manually resumes or deletes them, with no automatic archival or deletion
- When the app is offline, recurring expense instances are created in local storage immediately and synced when connectivity is restored
- How does budget reservation interact with actual budget availability - should users be warned if reservations exceed available budget?
- What happens when a user marks a recurring expense as reimbursable - does this apply to all future occurrences or just the current one?
- How should the system handle overlapping budget reservations when the same money is potentially reserved for multiple purposes?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow users to mark any expense as recurring during creation or editing
- **FR-002**: System MUST provide frequency options for recurring expenses: daily, weekly, monthly, yearly
- **FR-003**: System MUST persist recurring expense configuration (frequency, amount, category, description, anchor date) across app sessions
- **FR-003a**: System MUST automatically create new expense instances when the recurrence period arrives (e.g., monthly expense creates new instance on the same day each month)
- **FR-003b**: System MUST use the expense's date as the recurrence anchor when marking an expense as recurring (for existing expenses, use original date; for new expenses, use the date field value)
- **FR-003c**: System MUST create recurring expense instances in local storage immediately when scheduled, regardless of network connectivity, and sync them when online
- **FR-004**: System MUST clearly display recurring status and frequency when viewing expense details
- **FR-005**: System MUST allow users to convert existing non-recurring expenses to recurring expenses by transforming the original expense into a recurring template that remains visible with a recurring indicator
- **FR-005a**: System MUST create future expense instances as separate expenses from the recurring template, leaving the original template expense in place
- **FR-006**: System MUST allow users to convert recurring expenses back to non-recurring expenses
- **FR-007**: System MUST provide an option to enable budget reservation for any recurring expense
- **FR-008**: System MUST calculate reserved budget by summing all recurring expenses with budget reservation enabled for the current budget period being viewed (e.g., if viewing monthly budget, reserve for current month; if viewing yearly budget, reserve for current year)
- **FR-009**: System MUST display reserved budget amount in the budget overview
- **FR-010**: System MUST show available budget calculated as (total budget - reserved budget)
- **FR-011**: System MUST provide a "Recurring Expenses" menu item in the Settings screen
- **FR-012**: Recurring Expenses management screen MUST display a list of all recurring expenses with their frequency, amount, and category
- **FR-013**: Recurring Expenses management screen MUST allow users to view and edit any recurring expense
- **FR-014**: System MUST provide an option to pause and resume recurring expenses
- **FR-014a**: System MUST allow paused recurring expenses to remain paused indefinitely until the user manually resumes or deletes them (no automatic archival)
- **FR-015**: System MUST not automatically create new expense instances for paused recurring expenses when their recurrence period arrives
- **FR-016**: System MUST provide options when deleting a recurring expense: delete future occurrences only, or delete all occurrences including historical
- **FR-017**: System MUST provide a "Reimbursements" menu item in the Settings screen
- **FR-018**: Reimbursements screen MUST display all expenses marked as "reimbursable" or "reimbursed"
- **FR-019**: Reimbursements screen MUST allow filtering or grouping by reimbursement status (reimbursable vs. reimbursed)
- **FR-020**: Reimbursements screen MUST display summary totals: total pending reimbursements and total reimbursed amounts
- **FR-021**: Reimbursements screen MUST allow users to mark reimbursable expenses as reimbursed directly from the screen
- **FR-022**: Reimbursements screen MUST provide search and filter capabilities to find specific reimbursements

### Key Entities

- **Recurring Expense**: Represents an expense template that repeats on a schedule. Key attributes include amount, category, description, frequency (daily, weekly, monthly, yearly), anchor date (the reference date from which recurrences are calculated), budget reservation status (enabled/disabled), and active status (active/paused). When an existing expense is converted to recurring, it becomes the template and remains visible with a recurring indicator. This template generates separate expense instances based on the recurrence schedule starting from the anchor date.

- **Budget Reservation**: Represents budget allocated for upcoming recurring expenses. Key attributes include the associated recurring expense, reserved amount, and calculation period. This affects the available budget calculation but doesn't create actual expense entries until the recurrence period arrives.

- **Reimbursement**: (Extends existing Expense entity from Feature 012) Represents the reimbursement status of an expense. Attributes include reimbursement status (none, reimbursable, reimbursed) and reimbursement date.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can mark an expense as recurring and set its frequency in under 30 seconds
- **SC-002**: Budget overview accurately reflects reserved budget for recurring expenses with 100% calculation accuracy
- **SC-003**: Users can access the complete list of all recurring expenses from Settings in under 3 taps
- **SC-004**: Recurring expense configuration changes (pause, resume, edit) take effect immediately with zero delay
- **SC-005**: Users can view all reimbursable and reimbursed expenses in a single consolidated screen
- **SC-006**: Budget reservation calculations update in real-time when recurring expenses are added, modified, or removed
- **SC-007**: 90% of users successfully configure their first recurring expense without assistance
- **SC-008**: Zero instances of budget reservation miscalculations affecting user financial planning

## Assumptions

- The existing expense data model can be extended to include recurring expense properties (frequency, is_recurring flag, budget_reservation flag, is_paused flag)
- The app has a Settings screen where new menu items can be added
- Feature 012 (Expense Improvements) has been implemented, providing the reimbursement status functionality
- The budget calculation system is centralized and can be extended to incorporate budget reservations
- Users understand the concept of budget reservation (allocating money for future known expenses)
- Budget reservations should warn users but not prevent them from creating expenses even if available budget would go negative
- When a recurring expense is marked as reimbursable, this setting applies only to manually created instances, not automatically to all future occurrences
- The system uses standard calendar periods for recurrence calculation (daily = every 24 hours, weekly = every 7 days, monthly = same day each month, yearly = same date each year)
