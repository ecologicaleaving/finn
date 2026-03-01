# Feature Specification: Custom Category Icons

**Feature Branch**: `014-category-icons`
**Created**: 2026-02-05
**Status**: Draft
**Input**: User description: "pianifica delle icone delle categorie"

## Clarifications

### Session 2026-02-05

- Q: How should the system assign default icons to existing categories during migration? → A: Apply the smart default icon matching logic (P3) to existing category names during migration
- Q: Should the icon picker search support only Italian keywords, or multiple languages? → A: Support both Italian keywords and English Material Icons names
- Q: When a category icon is changed, should the update propagate immediately while the user is still in other screens, or only when they navigate/refresh? → A: Immediate live update across all visible screens without requiring navigation or manual refresh

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Categories with Visual Icons (Priority: P1)

Users see visual icons alongside category names throughout the app, making categories instantly recognizable and easier to distinguish at a glance.

**Why this priority**: This is the foundational visual improvement that benefits all users immediately. Icons make the UI more intuitive and reduce cognitive load when scanning expense lists and reports.

**Independent Test**: Can be fully tested by viewing any screen that displays categories (expense list, budget overview, dashboard) and verifying that each category shows its assigned icon.

**Acceptance Scenarios**:

1. **Given** a user is viewing the expense list, **When** they see expenses from different categories, **Then** each expense displays the category's icon alongside its name
2. **Given** a user is creating a new expense, **When** they open the category selector, **Then** all categories are displayed with their visual icons in a grid layout (3 per row)
3. **Given** a user is viewing the dashboard, **When** they see category breakdowns, **Then** each category shows its distinctive icon

---

### User Story 2 - Select Icons for Custom Categories (Priority: P2)

When creating or editing a custom category, users can choose an icon from a comprehensive icon library to visually represent that category.

**Why this priority**: This enables personalization for custom categories created by users, making the app more flexible and user-friendly for diverse expense tracking needs.

**Independent Test**: Can be tested by creating a new custom category, selecting an icon from the library, and verifying the icon appears correctly in all contexts where that category is displayed.

**Acceptance Scenarios**:

1. **Given** a user is creating a new category, **When** they tap the icon selection field, **Then** a searchable icon picker opens showing Material Design icons organized by category
2. **Given** the icon picker is open, **When** the user searches for keywords (e.g., "car", "food", "home"), **Then** relevant icons are filtered and displayed
3. **Given** the user selects an icon, **When** they save the category, **Then** the chosen icon persists and appears whenever that category is displayed
4. **Given** a user is editing an existing custom category, **When** they change the icon, **Then** the new icon updates across all past and future expenses using that category

---

### User Story 3 - Smart Default Icons for Categories (Priority: P3)

The system automatically suggests appropriate icons for categories based on category name analysis, reducing setup effort for users.

**Why this priority**: This is a quality-of-life enhancement that improves the onboarding experience and reduces friction, but users can still function without it using P2 functionality.

**Independent Test**: Can be tested by creating categories with common Italian names (e.g., "Spesa", "Benzina", "Ristorante") and verifying the system pre-selects contextually relevant icons.

**Acceptance Scenarios**:

1. **Given** a user creates a category named "Spesa" or "Alimentari", **When** the category form loads, **Then** a shopping cart icon is pre-selected by default
2. **Given** a user creates a category named "Benzina" or "Carburante", **When** the category form loads, **Then** a gas station icon is pre-selected by default
3. **Given** a user creates a category with an unrecognized name, **When** the category form loads, **Then** a generic category icon is pre-selected by default
4. **Given** the system pre-selected an icon, **When** the user disagrees with the suggestion, **Then** they can easily override it by selecting a different icon

---

### Edge Cases

- What happens when a category has no icon assigned (legacy data or data migration)?
  - During migration, apply smart default icon matching logic based on category name to automatically assign appropriate icons. If no match found, assign a generic "category" fallback icon
- What happens when the icon library doesn't contain a suitable icon for a specific category?
  - Allow users to select from the full Material Icons library (1000+ icons)
- How does the system handle icon display on very small screens or in compact views?
  - Icons scale appropriately and maintain minimum touch target sizes (44x44dp minimum)
- What happens if a user deletes a category that has an associated icon?
  - Icon mapping is removed along with the category (cascading behavior)
- How are icons handled when exporting/importing categories across devices?
  - Icon identifiers are stored as strings (icon names from Material Icons) ensuring cross-platform consistency

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST store an icon identifier for each category (both default and custom categories)
- **FR-002**: System MUST display category icons in all UI contexts where categories appear (expense list, category selector, budget overview, dashboard charts)
- **FR-003**: Users MUST be able to select an icon from the Material Design icon library when creating or editing custom categories
- **FR-004**: System MUST provide an icon picker interface with bilingual search functionality supporting both Italian keywords (e.g., "macchina", "cibo") and English Material Icons names (e.g., "car", "food")
- **FR-005**: System MUST organize icons in the picker by logical groups (e.g., "Shopping", "Transport", "Food", "Home", "Entertainment")
- **FR-006**: System MUST automatically suggest contextually appropriate icons for new categories based on category name analysis
- **FR-007**: System MUST use fallback icons for categories without assigned icons to maintain UI consistency
- **FR-008**: System MUST persist icon selections and ensure icons remain associated with categories across app restarts
- **FR-009**: System MUST propagate icon changes immediately and reactively to all visible screens when a category's icon is changed, without requiring navigation, manual refresh, or app restart
- **FR-010**: System MUST maintain backwards compatibility by applying smart default icon matching (based on category name analysis) to existing categories during migration, ensuring all categories have appropriate icons without requiring manual user assignment
- **FR-011**: Category icon selector MUST display icons in a grid layout (3 icons per row) for easy scanning
- **FR-012**: Icon picker MUST support both browsing and search interactions for icon discovery

### Key Entities

- **Category**: Represents an expense category (existing entity, enhanced with icon)
  - New attribute: `iconName` (string identifier from Material Icons library, e.g., "shopping_cart", "local_gas_station")
  - Existing attributes: id, name, groupId, isDefault, etc.

- **Icon Mapping**: Represents the smart default suggestions
  - Category name patterns (keywords)
  - Suggested icon identifier
  - Priority/confidence score for multiple matches

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can identify expense categories visually in under 2 seconds (compared to reading category names)
- **SC-002**: 90% of users successfully select an appropriate icon for custom categories on their first attempt
- **SC-003**: Icon search functionality returns relevant results for at least 95% of common expense-related keywords in both Italian and English
- **SC-004**: Smart default icon suggestions are accepted (not changed) by users 80% of the time for common Italian category names
- **SC-005**: All category icons display consistently across different screen sizes (phones, tablets) without layout issues
- **SC-006**: Category selector with icon grid layout reduces time to select a category by 30% compared to text-only dropdown

## Assumptions

- The app uses Material Design and has access to the full Material Icons library
- Categories are already stored in a database table (Supabase) that can be extended with additional fields
- The UI framework (Flutter) supports dynamic icon rendering from icon name identifiers
- Users are primarily Italian-speaking and category names will be in Italian
- Icon identifiers will use Material Icons naming convention (lowercase with underscores)
- The icon picker can leverage existing Flutter packages for Material Icon browsing/search
- Network connectivity is not required to display icons (icons are bundled with the app)

## Out of Scope

- Custom icon uploads (user-provided images/SVGs)
- Animated icons or Lottie animations
- Icon color customization beyond theme colors
- Third-party icon libraries (only Material Design icons)
- Icon version management or fallback for deprecated icons
- Icon usage analytics or popularity tracking
- Emoji support as category icons
- Icon accessibility features beyond standard Material Design guidelines
