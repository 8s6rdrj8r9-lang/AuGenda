// AuDHDLayout.swift
// AuGenda Layout System
//
// - ScreenContainer: Standard padding, max width, safe area
// - SectionHeader: Labeled section with optional collapse
// - NavigationLayout: Tab-based navigation (mobile-first, desktop sidebar)

import SwiftUI

// MARK: - Screen Container

/// Standard container for all screens with proper padding, max width, and constraints
struct ScreenContainer<Content: View>: View {
    let content: Content
    var horizontalPadding: CGFloat = Tokens.Spacing.lg
    var verticalPadding: CGFloat = Tokens.Spacing.lg
    var maxWidth: CGFloat = Tokens.Layout.maxCardWidth
    var backgroundColor: Color = Color.appBackground

    init(
        horizontalPadding: CGFloat = Tokens.Spacing.lg,
        verticalPadding: CGFloat = Tokens.Spacing.lg,
        maxWidth: CGFloat = Tokens.Layout.maxCardWidth,
        backgroundColor: Color = Color.appBackground,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.maxWidth = maxWidth
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: maxWidth)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .background(backgroundColor)
    }
}

// MARK: - Section Header

/// Labeled section with optional collapse/expand
struct SectionHeader: View {
    let title: String
    let subtitle: String?
    @Binding var isExpanded: Bool
    var isCollapsible: Bool = false

    var body: some View {
        HStack(spacing: Tokens.Spacing.base) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(title)
                    .font(Tokens.Typography.h3)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.appTextPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextSecondary)
                }
            }

            Spacer()

            if isCollapsible {
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Tokens.Spacing.base)
        .padding(.vertical, Tokens.Spacing.md)
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @State private var isExpanded: Bool = true
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        isExpanded: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isExpanded = State(initialValue: isExpanded)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: title,
                subtitle: subtitle,
                isExpanded: $isExpanded,
                isCollapsible: true
            )

            if isExpanded {
                Divider()
                    .padding(.horizontal, Tokens.Spacing.base)

                VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                    content
                }
                .padding(Tokens.Spacing.base)
                .transition(.opacity)
            }
        }
        .background(Color.appBackgroundSecondary)
        .cornerRadius(Tokens.Border.radiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium)
                .strokeBorder(Color.appBorder, lineWidth: Tokens.Border.widthDefault)
        )
    }
}

// MARK: - Tab Navigation Item

enum NavigationTab: String, CaseIterable {
    case today = "Today"
    case tasks = "Tasks"
    case blocks = "Blocks"
    case household = "Household"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .today: return "calendar.day.timeline.left"
        case .tasks: return "checklist"
        case .blocks: return "square.grid.2x2.fill"
        case .household: return "person.3.fill"
        case .settings: return "gear"
        }
    }

    var label: String {
        rawValue
    }
}

// MARK: - Tab Bar (Mobile)

struct TabBar: View {
    @Binding var selectedTab: NavigationTab
    var tabs: [NavigationTab] = NavigationTab.allCases

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        VStack(spacing: Tokens.Spacing.xs) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .semibold))

                            Text(tab.label)
                                .font(Tokens.Typography.caption)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: Tokens.Spacing.touchMinimum)
                        .foregroundColor(
                            selectedTab == tab
                                ? Tokens.Color.primary
                                : Color.appTextSecondary
                        )
                    }
                    .buttonStyle(.plain)

                    if tab != tabs.last {
                        Divider()
                            .frame(height: Tokens.Spacing.xl)
                    }
                }
            }
            .background(Color.appBackground)
        }
    }
}

// MARK: - Sidebar Navigation (Desktop)

struct Sidebar: View {
    @Binding var selectedTab: NavigationTab
    var tabs: [NavigationTab] = NavigationTab.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            ForEach(tabs, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: Tokens.Spacing.base) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 24)

                        Text(tab.label)
                            .font(Tokens.Typography.body)
                            .fontWeight(.semibold)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Tokens.Spacing.touchMinimum)
                    .padding(.horizontal, Tokens.Spacing.base)
                    .background(
                        selectedTab == tab
                            ? Tokens.Color.primary.opacity(0.15)
                            : Color.clear
                    )
                    .cornerRadius(Tokens.Border.radiusSmall)
                    .foregroundColor(
                        selectedTab == tab
                            ? Tokens.Color.primary
                            : Color.appTextPrimary
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(Tokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackgroundSecondary)
        .frame(width: 280)
    }
}

// MARK: - Navigation Layout

struct NavigationLayout<Content: View>: View {
    @Binding var selectedTab: NavigationTab
    let content: Content
    var tabs: [NavigationTab] = NavigationTab.allCases

    init(
        selectedTab: Binding<NavigationTab>,
        tabs: [NavigationTab] = NavigationTab.allCases,
        @ViewBuilder content: () -> Content
    ) {
        self._selectedTab = selectedTab
        self.content = content()
        self.tabs = tabs
    }

    var body: some View {
        #if os(iOS)
        ZStack(alignment: .bottom) {
            content

            TabBar(selectedTab: $selectedTab, tabs: tabs)
        }
        #else
        HStack(spacing: 0) {
            Sidebar(selectedTab: $selectedTab, tabs: tabs)

            content
        }
        #endif
    }
}

// MARK: - Breadcrumb Navigation (Desktop)

struct Breadcrumb: View {
    let path: [String]

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            ForEach(Array(path.enumerated()), id: \.offset) { index, item in
                Text(item)
                    .font(Tokens.Typography.caption)
                    .foregroundColor(
                        index == path.count - 1
                            ? Color.appTextPrimary
                            : Color.appTextSecondary
                    )

                if index < path.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Tokens.Spacing.lg)
        .padding(.vertical, Tokens.Spacing.base)
        .background(Color.appBackgroundSecondary)
    }
}

// MARK: - Empty State

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        VStack(spacing: Tokens.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Color.appTextSecondary)

            VStack(spacing: Tokens.Spacing.sm) {
                Text(title)
                    .font(Tokens.Typography.h3)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.appTextPrimary)

                Text(message)
                    .font(Tokens.Typography.body)
                    .foregroundColor(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
            }

            if let action = action, let actionLabel = actionLabel {
                AuDHDButton(actionLabel, style: .primary, action: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Tokens.Spacing.xl)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selectedTab: NavigationTab = .today

    NavigationLayout(selectedTab: $selectedTab) {
        ScreenContainer {
            VStack(spacing: Tokens.Spacing.xl) {
                SectionHeader(
                    title: "Today",
                    subtitle: "May 26, 2026",
                    isExpanded: .constant(true)
                )

                CollapsibleSection(title: "In Progress", isExpanded: true) {
                    Text("Item 1")
                    Text("Item 2")
                }

                EmptyState(
                    icon: "tray",
                    title: "Nothing here",
                    message: "You've completed all your tasks for today!",
                    action: { print("Add task") },
                    actionLabel: "Add New Task"
                )
            }
        }
    }
}
