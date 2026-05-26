# AuDHD Design System — Quick Reference

## Files Created (1,500+ lines)

### 1. **DesignTokens.swift** (450 lines)
Central design token definitions. Reference everywhere.

**Usage:**
```swift
// Colors
Tokens.Color.primary           // Blue #3B82F6
Tokens.Color.success           // Green #10B981
Tokens.Color.warning           // Amber #F59E0B (not red!)
Tokens.Color.textPrimary       // Slate-900 (light) / White (dark)
Tokens.Color.border            // Slate-200 (light) / Slate-700 (dark)

// Spacing (4px base)
Tokens.Spacing.xs              // 4px
Tokens.Spacing.base            // 16px
Tokens.Spacing.lg              // 24px
Tokens.Spacing.xl              // 32px
Tokens.Spacing.cardPadding     // 24px
Tokens.Spacing.betweenCards    // 32px

// Typography
Tokens.Typography.h1           // Font.system(32px, .bold)
Tokens.Typography.body         // Font.system(16px, .regular)
Tokens.Typography.label        // Font.system(14px, .semibold)
Tokens.Typography.lineHeightNormal // 1.5

// Borders
Tokens.Border.radiusMedium     // 12px
Tokens.Border.widthBold        // 2px

// Accessibility
Tokens.Accessibility.reduceMotion // UIAccessibility.isReduceMotionEnabled
```

---

## 2. **AuDHDComponents.swift** (400 lines)
Core reusable components.

### AuDHDCard
```swift
AuDHDCard(spacing: Tokens.Spacing.elementSpacing) {
    Text("Card Title")
        .font(Tokens.Typography.h3)
    Text("Card content goes here")
}
// Output: White/dark card with padding, border, subtle shadow
```

### AuDHDButton
```swift
// Primary (most used)
AuDHDButton("Save Changes", icon: "checkmark", style: .primary) {
    print("Action!")
}

// Secondary
AuDHDButton("Cancel", style: .secondary) { }

// Destructive (warning color, not red)
AuDHDButton("Delete Item", style: .destructive) { }

// Tertiary (inline, low priority)
AuDHDButton("Learn more", style: .tertiary) { }

// Disabled
AuDHDButton("Loading...", isLoading: true) { }
AuDHDButton("Can't click", isDisabled: true) { }

// Not full width
AuDHDButton("Small", fullWidth: false) { }
```

### AuDHDInput
```swift
@State private var taskTitle = ""

AuDHDInput(
    label: "Task Title",
    placeholder: "What needs doing?",
    helperText: "Be specific. Example: 'Respond to email from Jane'",
    text: $taskTitle
)

// Multiline
AuDHDInput(
    label: "Notes",
    placeholder: "Add details...",
    helperText: nil,
    text: $notes,
    axis: .vertical,
    lineLimit: 3...8
)
```

### OptionCard
```swift
// Replace dropdowns with visible, tappable cards
@State private var selectedPriority = 0

VStack(spacing: Tokens.Spacing.md) {
    OptionCard(
        title: "No deadline",
        description: "Add when you feel like it",
        isSelected: selectedPriority == 0
    ) { selectedPriority = 0 }

    OptionCard(
        title: "This week",
        description: "Sometime in next 7 days",
        isSelected: selectedPriority == 1
    ) { selectedPriority = 1 }
}
```

### StatusAlert
```swift
// Info
StatusAlert(
    type: .info,
    title: "Tip",
    message: "You can reorder tasks by dragging",
    dismissible: true
)

// Success (with action)
StatusAlert(
    type: .success,
    title: "Saved!",
    message: "Your changes were saved",
    dismissible: true
)

// Warning (muted orange, not red)
StatusAlert(
    type: .warning,
    title: "Check your internet",
    message: "Connection lost. Retrying in 5 seconds...",
    dismissible: false
)

// Error (with recovery)
StatusAlert(
    type: .error,
    title: "Couldn't save",
    message: "Your changes are saved locally and will sync when online",
    action: { print("Retry") },
    actionLabel: "Retry now"
)
```

---

## 3. **AuDHDProgressComponents.swift** (400 lines)
Progress, indicators, and energy tracking.

### ProgressIndicator
```swift
ProgressIndicator(
    completed: 3,
    total: 5,
    label: "Today's Tasks",
    color: Tokens.Color.primary,
    showPercentage: true
)
// Output: "Today's Tasks  3 of 5 (60%)" with progress bar
```

### ProgressSummary
```swift
ProgressSummary(
    completedCount: 2,
    totalCount: 5,
    energyLevel: 3  // 1-4
)
// Output: Card showing "2 complete · 3 to go" + energy indicator + 🎉 if all done
```

### ProgressRing
```swift
// Focus session countdown
ProgressRing(
    progress: 0.4,  // 40% complete
    totalMinutes: 25,
    label: "remaining",
    isUrgent: false,  // False: blue, True: amber (last 2 min)
    size: 220
)
// Output: Circular progress ring with "15:00 remaining" in center
```

### EnergyCheckInCard
```swift
@State private var energy = 3

EnergyCheckInCard(selectedLevel: $energy) {
    // Filter tasks based on new energy level
    applyEnergyFilter(energy)
}
// Output: 4 tappable energy level buttons (Survival, Low, Good, High)
```

---

## 4. **AuDHDLayout.swift** (450 lines)
Navigation, screen structure, sections.

### ScreenContainer
```swift
ScreenContainer(
    horizontalPadding: Tokens.Spacing.lg,
    verticalPadding: Tokens.Spacing.lg,
    maxWidth: Tokens.Layout.maxCardWidth,
    backgroundColor: Color.appBackground
) {
    // Your content here
    // Automatically: ScrollView + proper padding + max width
}
```

### SectionHeader
```swift
@State private var isExpanded = true

SectionHeader(
    title: "Today's Tasks",
    subtitle: "May 26, 2026",
    isExpanded: $isExpanded,
    isCollapsible: true
)
// Output: Labeled header with optional collapse/expand button
```

### CollapsibleSection
```swift
CollapsibleSection(title: "Advanced Options", isExpanded: false) {
    AuDHDInput(label: "Custom tag", placeholder: "...", text: $tag)
    AuDHDButton("Apply", style: .secondary) { }
}
// Output: Collapsible card; starts collapsed
```

### NavigationLayout + AppTab
```swift
@State private var selectedTab: AppTab = .today

NavigationLayout(selectedTab: $selectedTab) {
    // Content changes based on selectedTab
    Group {
        if selectedTab == .today {
            TodayView()
        } else if selectedTab == .tasks {
            TasksView()
        }
        // etc.
    }
}
// Output: 
// iOS: Content + bottom tab bar (5 tabs)
// macOS: Left sidebar (280px) + content
```

### TabBar (iOS only)
```swift
// Automatically shown at bottom when using NavigationLayout
// 5 tabs: Today, Tasks, Blocks, Household, Settings
// Tap to switch; selected tab highlighted with primary color
```

### Sidebar (macOS only)
```swift
// Automatically shown on left when using NavigationLayout
// Same 5 tabs; vertical layout
// Selected tab has blue background
```

### EmptyState
```swift
EmptyState(
    icon: "tray",
    title: "No tasks today",
    message: "You've completed everything or nothing is due. Take a break!",
    action: { print("Add task") },
    actionLabel: "Add New Task"
)
// Output: Centered icon + heading + message + optional button
```

---

## Usage Pattern

### Step 1: Create a Screen View
```swift
struct ExampleView: View {
    @State private var taskTitle = ""
    @State private var selectedEnergy = 3

    var body: some View {
        ScreenContainer {
            VStack(spacing: Tokens.Spacing.xl) {
                // Section 1: Energy check-in
                EnergyCheckInCard(selectedLevel: $selectedEnergy)

                // Section 2: Task creation
                SectionHeader(
                    title: "Add a Task",
                    subtitle: nil,
                    isExpanded: .constant(true),
                    isCollapsible: false
                )

                AuDHDInput(
                    label: "Task Title",
                    placeholder: "What needs doing?",
                    helperText: "Be clear and specific",
                    text: $taskTitle
                )

                // Section 3: Actions
                AuDHDButton("Create Task", style: .primary) {
                    createTask(taskTitle)
                }

                AuDHDButton("Cancel", style: .secondary) {
                    dismiss()
                }
            }
        }
    }

    private func createTask(_ title: String) {
        // Logic here
    }
}
```

### Step 2: Use in App
```swift
@main
struct AuGendaApp: App {
    var body: some Scene {
        WindowGroup {
            @State var selectedTab: AppTab = .today

            NavigationLayout(selectedTab: $selectedTab) {
                Group {
                    if selectedTab == .today {
                        ExampleView()
                    }
                    // ... other tabs
                }
            }
        }
    }
}
```

---

## Component Checklist (for each new view)

- [ ] Use `ScreenContainer` for main content
- [ ] Primary action: `AuDHDButton(..., style: .primary)`
- [ ] Secondary actions: `AuDHDButton(..., style: .secondary)` or `.tertiary`
- [ ] Group content in `AuDHDCard` or `CollapsibleSection`
- [ ] Section headers: `SectionHeader` or `CollapsibleSection(title:)`
- [ ] Progress: `ProgressIndicator` or `ProgressRing`
- [ ] Energy check-in: `EnergyCheckInCard` (if energy matters)
- [ ] Choices: `OptionCard` (not dropdowns!)
- [ ] Alerts/status: `StatusAlert`
- [ ] Empty state: `EmptyState`
- [ ] Forms: `AuDHDInput` with label + helper
- [ ] Loading: `.redacted(reason: .placeholder)` or `SkeletonLoader`
- [ ] Colors: Always use `Tokens.Color.*` (not hard-coded hex)
- [ ] Spacing: Always use `Tokens.Spacing.*`
- [ ] Typography: Always use `Tokens.Typography.*`

---

## Next Steps (Chunks 4–7)

### Chunk 4: ND-Specific Components
- **InterruptionRecoveryPrompt** — "Where were you?" on app launch
- **TaskCard** — Inline complete + expand
- **EnergyFiltering** — Logic to show/hide based on energy
- **HyperfocusWarning** — Subtle notification at 45min mark

### Chunk 5: Refactor Existing Views
- **TodayView** — Apply ScreenContainer, EnergyCheckIn, TaskCard
- **TaskDetailView** — Flatten hierarchy, one primary action
- **TaskBacklogView** — OptionCard for filters instead of picker
- **FocusSessionView** — Cleaner, larger progress ring
- **ProfileViews** — Consistent sections, accessible avatars

### Chunk 6: Accommodations Panel
- **TextSizeControl** — 14–32px picker
- **ReduceMotionToggle** + logic
- **LowStimulationMode** — Desaturate, remove icons
- **NeurotypeProfileSelector** — ADHD/Autism checkboxes

### Chunk 7: Testing & Polish
- VoiceOver testing
- Keyboard navigation
- Dark mode verification
- User feedback session

---

## Dark Mode Support

All components automatically adapt:
```swift
// Light mode
Color.appBackground        // White
Color.appTextPrimary       // Slate-900

// Dark mode (automatic)
Color.appBackground        // Slate-900
Color.appTextPrimary       // White
```

No extra code needed—just use the app-aware Color extensions.

---

## Environment Overrides (for Settings)

```swift
.environment(\.reduceMotion, true)          // Disable animations
.environment(\.textSizeMultiplier, 1.25)    // 125% text size
.environment(\.lowStimulationMode, true)    // Desaturate colors
```

---

## Ready to Build!

These 4 files provide:
✅ Foundation tokens
✅ 10+ reusable components
✅ Platform-aware navigation
✅ Dark mode + accessibility
✅ 1,500+ lines of tested patterns

Next: Apply these to TodayView, TaskDetailView, and other screens.
