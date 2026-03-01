# Feature Specification: Cash Payment Default Fix & Admin Expense Management

**Feature Branch**: `001-admin-expenses-cash-fix`
**Created**: 2026-01-18
**Status**: Draft
**Input**: User description: "devo chiederti due modifiche: 1- come metodo di pagamento fa sì che sia selezionato di default "Contanti" , che non ci sia bisogno di modificare la selezione ( al momento risulta selezionato di default, ma devo comunque selezionarlo di nuovo, se no non procede al salvataggio. ; 2 - come amministratore voglio poter aggiungere e modificare le spese degli utenti del mio gruppo;"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Cash Payment Default Selection (Priority: P1)

When a user creates a new expense, the cash payment method should be automatically selected and immediately functional without requiring manual reselection. Currently, even though "Contanti" (Cash) appears as selected, users must click it again before the expense can be saved.

**Why this priority**: This is a critical usability bug that blocks basic expense entry workflow. Every user creating an expense with cash (likely the most common payment method) is forced to perform an extra, unnecessary step. This creates friction in the primary user flow and may lead to user frustration or data entry errors.

**Independent Test**: Can be fully tested by creating a new expense, verifying that "Contanti" is pre-selected, and immediately attempting to save the expense without touching the payment method selector. The save should succeed.

**Acceptance Scenarios**:

1. **Given** a user is on the expense creation screen, **When** the screen loads, **Then** the "Contanti" payment method is visually selected and functionally active
2. **Given** the expense creation screen has loaded with "Contanti" pre-selected, **When** the user fills in expense details (amount, category, date) and clicks save without touching the payment method, **Then** the expense is successfully saved with "Contanti" as the payment method
3. **Given** a user has entered expense details with the default "Contanti" selection, **When** the user attempts to proceed to the next step or save, **Then** no validation error appears requiring payment method reselection

---

### User Story 2 - Admin Add Expenses for Group Members (Priority: P2)

As a group administrator, I need the ability to add new expenses on behalf of any user in my group. This allows administrators to input expenses for group members who may not have access to the app or who need assistance with data entry.

**Why this priority**: This is an important administrative capability that extends group management functionality. While not blocking basic operations, it enables administrators to maintain complete expense records for their groups, particularly useful for families with children or when handling shared expenses.

**Independent Test**: Can be fully tested by logging in as a group administrator, navigating to the expense creation interface, selecting a group member from a user selector, entering expense details, and verifying the expense is saved and attributed to the selected user.

**Acceptance Scenarios**:

1. **Given** a user is logged in as a group administrator, **When** they access the expense creation screen, **Then** they see an option to select which group member the expense is for
2. **Given** an administrator has selected a group member, **When** they create an expense with all required details, **Then** the expense is saved and appears in the selected member's expense history
3. **Given** an administrator creates an expense for another user, **When** the expense is saved, **Then** the group member can view the expense in their own expense list
4. **Given** a non-administrator user accesses the expense creation screen, **When** the screen loads, **Then** no user selector is visible and expenses are attributed only to themselves

---

### User Story 3 - Admin Edit Expenses for Group Members (Priority: P2)

As a group administrator, I need the ability to modify existing expenses created by any user in my group. This allows administrators to correct errors, update details, or adjust categorization for group members' expenses.

**Why this priority**: This complements the admin add functionality and provides complete administrative control over group expense data. Essential for maintaining data accuracy and handling corrections without requiring users to make changes themselves.

**Independent Test**: Can be fully tested by logging in as a group administrator, viewing a group member's expense list, selecting an expense created by that member, editing its details (amount, category, date, payment method), saving the changes, and verifying the updated expense reflects the modifications.

**Acceptance Scenarios**:

1. **Given** a user is logged in as a group administrator, **When** they view any group member's expense list, **Then** they can select and open any expense for editing
2. **Given** an administrator is editing another user's expense, **When** they modify expense details and save, **Then** the changes are persisted and visible to both the administrator and the expense owner
3. **Given** an administrator modifies another user's expense, **When** the expense is updated, **Then** the original creator information is preserved (showing who created it and who last modified it)
4. **Given** a non-administrator user views their own expenses, **When** they attempt to edit an expense created by an administrator, **Then** they can edit it normally without restrictions

---

### Edge Cases

- **Removed group member**: When an administrator tries to add/edit expenses for a user who is no longer in the group, the operation is allowed and the expense remains linked to the removed user's historical record
- **Concurrent edits**: When both the expense owner and an administrator edit the same expense simultaneously, the first save wins and the second user sees an error message that the expense was already modified
- **Administrator demotion**: If an administrator is demoted to regular user while viewing another member's expense details, access is immediately revoked with an error message and redirect to their own expenses view
- **Audit trail visibility**: The system displays creator and last modified by fields on expense details, visible to all users for transparency and accountability
- **Default payment method deletion**: When the "Contanti" payment method is deleted or deactivated, the system automatically selects the first available payment method; if no payment methods exist, an error message is shown requiring payment method setup

## Clarifications

### Session 2026-01-18

- Q: When an administrator tries to add or edit an expense for a user who has been removed from the group, what should happen? → A: Allow the operation - expense remains linked to the removed user's historical record
- Q: How should the system handle concurrent edits if both the expense owner and an administrator edit the same expense simultaneously? → A: First save wins - second user sees an error message that the expense was already modified
- Q: What happens if an administrator is demoted to regular user while viewing another member's expense details? → A: Immediately revoke access - show error and redirect to own expenses view
- Q: How should the system display audit information (who created and who last modified an expense) to users? → A: Always visible - show creator and last modified by fields on expense details for all users
- Q: What happens when the default "Contanti" payment method is deleted or deactivated? → A: Auto-select first available payment method - if none exist, show error requiring payment method setup

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST initialize the "Contanti" payment method as both visually selected and functionally active when the expense creation screen loads
- **FR-002**: System MUST allow expenses to be saved immediately with the pre-selected "Contanti" payment method without requiring user interaction with the payment method selector
- **FR-003**: System MUST display a user selector on the expense creation screen when the current user has administrator privileges for the group
- **FR-004**: System MUST allow administrators to create expenses that are attributed to any group member selected from the user selector
- **FR-005**: System MUST allow administrators to view and access expense lists for all members of their group
- **FR-006**: System MUST allow administrators to modify existing expenses created by any member of their group
- **FR-007**: System MUST preserve the original creator information when an administrator modifies another user's expense
- **FR-008**: System MUST hide the user selector from non-administrator users on the expense creation screen
- **FR-009**: System MUST enforce administrator privilege checks before allowing creation or modification of other users' expenses
- **FR-010**: System MUST synchronize expense changes across all relevant views (creator's view, group view, administrator view) in real-time or near real-time
- **FR-011**: System MUST allow administrators to add or edit expenses for users who have been removed from the group, maintaining the link to the removed user's historical record
- **FR-012**: System MUST implement optimistic locking for expense edits, where the first save succeeds and subsequent concurrent save attempts receive an error message indicating the expense was already modified
- **FR-013**: System MUST immediately revoke access and redirect demoted users to their own expenses view when administrator privileges are removed during an active session viewing another member's expense details
- **FR-014**: System MUST display creator and last modified by information on expense details, visible to all users regardless of role
- **FR-015**: System MUST automatically select the first available payment method when "Contanti" is deleted or deactivated, and display an error message requiring payment method setup if no payment methods exist

### Key Entities

- **Expense**: Represents a financial transaction with attributes including amount, category, date, payment method, creator (user who owns the expense), and last modified by (user who last edited it)
- **User**: Represents a person using the app with attributes including role/permissions within their group (administrator or regular member)
- **Group**: Represents a collection of users sharing budget tracking, with hierarchical permissions where administrators have elevated privileges
- **Payment Method**: Represents a way to pay for expenses, including "Contanti" (Cash) as the default option

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can create a cash expense and save it in under 10 seconds without needing to reselect the payment method
- **SC-002**: 100% of expense creation attempts with default cash payment succeed on first try without validation errors
- **SC-003**: Administrators can add an expense for any group member in under 15 seconds from the expense creation screen
- **SC-004**: Administrators can modify any group member's expense with changes visible to all relevant users within 2 seconds
- **SC-005**: Zero unauthorized expense modifications occur (non-administrators cannot edit other users' expenses)
- **SC-006**: User reports of payment method selection friction decrease to zero after fix deployment

## Assumptions

- The "Contanti" (Cash) payment method exists as a standard payment option in the system
- Group administrator roles are already defined and enforced in the current system
- The expense creation screen is a shared interface for both regular users and administrators
- Users can view their own expense history regardless of who created or modified the expense
- The system maintains audit information (creator, last modified by) for expenses
- All group members have the ability to view expenses attributed to them, regardless of who created them
- The fix for the cash payment default selection will not affect other payment method selections
- Administrators have full read/write access to all group data, not just their own expenses
