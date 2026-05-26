// AuDHDComponents.swift
// AuGenda Core Components
//
// Foundational reusable components built on Design Tokens.
// - AuDHDCard: Content container with consistent padding, spacing, borders
// - AuDHDButton: Primary, secondary, and destructive button styles
// - AuDHDInput: Text input with label, helper text, clear state handling
// - OptionCard: Choice selector (replaces dropdown)
// - StatusAlert: Info/warning/error/success boxes

import SwiftUI

// MARK: - AuDHD Card

/// Isolated content container with consistent spacing and styling
struct AuDHDCard<Content: View>: View {
    let content: Content
    var spacing: CGFloat = Tokens.Spacing.elementSpacing
    var isSeparated: Bool = true  // Add top border if in a list

    init(
        spacing: CGFloat = Tokens.Spacing.elementSpacing,
        isSeparated: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.spacing = spacing
        self.isSeparated = isSeparated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(Tokens.Spacing.cardPadding)
        .background(Color.appBackground)
        .cornerRadius(Tokens.Border.radiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium)
                .strokeBorder(
                    Color.appBorder,
                    lineWidth: Tokens.Border.widthDefault
                )
        )
        .shadow(
            color: Tokens.Shadow.subtle.color,
            radius: Tokens.Shadow.subtle.radius,
            x: Tokens.Shadow.subtle.x,
            y: Tokens.Shadow.subtle.y
        )
    }
}

// MARK: - AuDHD Button

enum AuDHDButtonStyle {
    case primary
    case secondary
    case tertiary
    case destructive
}

struct AuDHDButton: View {
    let title: String
    let icon: String?
    let style: AuDHDButtonStyle
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var fullWidth: Bool = true

    init(
        _ title: String,
        icon: String? = nil,
        style: AuDHDButtonStyle = .primary,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        fullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.fullWidth = fullWidth
    }

    var body: some View {
        Button(action: isLoading || isDisabled ? {} : action) {
            HStack(spacing: Tokens.Spacing.base) {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }

                Text(title)
                    .font(Tokens.Typography.label)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .frame(height: Tokens.Spacing.touchMinimum)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, Tokens.Spacing.buttonPaddingH)
            .foregroundColor(foregroundColor)
            .background(backgroundColor)
            .cornerRadius(Tokens.Border.radiusLarge)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge)
                    .strokeBorder(borderColor, lineWidth: Tokens.Border.widthDefault)
            )
        }
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.6 : 1.0)
        .focusable()
        .focused()
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:
            return .black
        case .secondary, .tertiary:
            return Color.appTextPrimary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return Tokens.Color.primary
        case .secondary:
            return Color.appBackgroundSecondary
        case .tertiary:
            return .clear
        case .destructive:
            return Tokens.Color.warning
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary, .destructive:
            return .clear
        case .secondary:
            return Color.appBorder
        case .tertiary:
            return .clear
        }
    }
}

// MARK: - AuDHD Input

struct AuDHDInput: View {
    let label: String
    let placeholder: String
    let helperText: String?
    @Binding var text: String
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int>? = 1...1

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            // Label
            Text(label)
                .font(Tokens.Typography.label)
                .fontWeight(.semibold)
                .foregroundColor(Color.appTextPrimary)

            // Input
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(lineLimit)
                .font(Tokens.Typography.body)
                .padding(Tokens.Spacing.base)
                .background(Color.appBackground)
                .border(
                    Color.appBorder,
                    width: Tokens.Border.widthBold
                )
                .cornerRadius(Tokens.Border.radiusSmall)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Border.radiusSmall)
                        .strokeBorder(
                            Color.appBorder,
                            lineWidth: Tokens.Border.widthBold
                        )
                )

            // Helper text
            if let helperText = helperText {
                Text(helperText)
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Color.appTextSecondary)
            }
        }
    }
}

// MARK: - Option Card (choice selector)

struct OptionCard: View {
    let title: String
    let description: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                HStack(spacing: Tokens.Spacing.base) {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                        Text(title)
                            .font(Tokens.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.appTextPrimary)

                        if let description = description {
                            Text(description)
                                .font(Tokens.Typography.caption)
                                .foregroundColor(Color.appTextSecondary)
                        }
                    }

                    Spacer()

                    // Selection indicator
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(
                            isSelected ? Tokens.Color.primary : Color.appBorder
                        )
                }
                .padding(Tokens.Spacing.base)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.appBackgroundSecondary : Color.appBackground)
            .cornerRadius(Tokens.Border.radiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium)
                    .strokeBorder(
                        isSelected ? Tokens.Color.primary : Color.appBorder,
                        lineWidth: Tokens.Border.widthBold
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Alert

enum StatusAlertType {
    case info
    case success
    case warning
    case error
}

struct StatusAlert: View {
    let type: StatusAlertType
    let title: String
    let message: String
    var icon: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil
    var dismissible: Bool = true
    @State private var isShown = true

    var body: some View {
        if isShown {
            HStack(alignment: .top, spacing: Tokens.Spacing.base) {
                // Icon
                VStack {
                    Image(systemName: icon ?? defaultIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                .frame(width: 24)
                .padding(.top, Tokens.Spacing.xs)

                // Content
                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    Text(title)
                        .font(Tokens.Typography.label)
                        .fontWeight(.semibold)
                        .foregroundColor(titleColor)

                    Text(message)
                        .font(Tokens.Typography.body)
                        .foregroundColor(Color.appTextPrimary)

                    // Action button
                    if let action = action, let actionLabel = actionLabel {
                        Button(actionLabel) {
                            action()
                        }
                        .font(Tokens.Typography.label)
                        .foregroundColor(actionColor)
                        .padding(.top, Tokens.Spacing.sm)
                    }
                }

                Spacer()

                // Dismiss button
                if dismissible {
                    Button(action: { isShown = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color.appTextSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Tokens.Spacing.base)
            .background(backgroundColor)
            .cornerRadius(Tokens.Border.radiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium)
                    .strokeBorder(
                        borderColor,
                        lineWidth: Tokens.Border.widthDefault
                    )
            )
        }
    }

    private var defaultIcon: String {
        switch type {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch type {
        case .info: return Tokens.Color.info
        case .success: return Tokens.Color.success
        case .warning: return Tokens.Color.warning
        case .error: return Tokens.Color.error
        }
    }

    private var titleColor: Color {
        switch type {
        case .info: return Tokens.Color.info
        case .success: return Tokens.Color.success
        case .warning: return Tokens.Color.warning
        case .error: return Tokens.Color.error
        }
    }

    private var actionColor: Color {
        switch type {
        case .info: return Tokens.Color.info
        case .success: return Tokens.Color.success
        case .warning: return Tokens.Color.warning
        case .error: return Tokens.Color.error
        }
    }

    private var backgroundColor: Color {
        switch type {
        case .info: return Tokens.Color.info.opacity(0.1)
        case .success: return Tokens.Color.success.opacity(0.1)
        case .warning: return Tokens.Color.warning.opacity(0.1)
        case .error: return Tokens.Color.error.opacity(0.1)
        }
    }

    private var borderColor: Color {
        switch type {
        case .info: return Tokens.Color.info.opacity(0.3)
        case .success: return Tokens.Color.success.opacity(0.3)
        case .warning: return Tokens.Color.warning.opacity(0.3)
        case .error: return Tokens.Color.error.opacity(0.3)
        }
    }
}

// MARK: - Color Helpers (extension on SwiftUI.Color)

extension Color {
    static let appBackground = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(AppColor.slate900) : UIColor(AppColor.white) })
    static let appBackgroundSecondary = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(AppColor.slate800) : UIColor(AppColor.slate50) })
    static let appTextPrimary = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(AppColor.white) : UIColor(AppColor.slate900) })
    static let appTextSecondary = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(AppColor.slate400) : UIColor(AppColor.slate600) })
    static let appBorder = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(AppColor.slate700) : UIColor(AppColor.slate200) })
    static let appAccent = AppColor.blue500
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: Tokens.Spacing.xl) {
            // Card example
            AuDHDCard {
                Text("Card Title")
                    .font(Tokens.Typography.h3)
                Text("This is content inside a card")
                    .font(Tokens.Typography.body)
            }

            // Button examples
            AuDHDButton("Primary Button", icon: "checkmark", style: .primary) {}
            AuDHDButton("Secondary Button", style: .secondary) {}
            AuDHDButton("Destructive Button", style: .destructive) {}

            // Input example
            AuDHDInput(
                label: "Task Title",
                placeholder: "What needs doing?",
                helperText: "Be specific",
                text: .constant("Example task")
            )

            // Option cards
            VStack(spacing: Tokens.Spacing.md) {
                OptionCard(title: "Option 1", description: "This is selected", isSelected: true) {}
                OptionCard(title: "Option 2", description: "This is not selected", isSelected: false) {}
            }

            // Status alerts
            StatusAlert(type: .info, title: "Information", message: "This is an info message")
            StatusAlert(type: .success, title: "Success!", message: "Your changes were saved")
            StatusAlert(type: .warning, title: "Warning", message: "Check your connection", dismissible: true)
            StatusAlert(type: .error, title: "Error", message: "Something went wrong", action: { print("Retry") }, actionLabel: "Retry")
        }
        .padding(Tokens.Spacing.lg)
    }
    .background(Color.appBackground)
}
