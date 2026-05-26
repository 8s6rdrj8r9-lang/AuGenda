// AuDHDProgressComponents.swift
// AuGenda Progress & Indicator Components
//
// - ProgressIndicator: Bar with count (3 of 5)
// - ProgressSummary: Daily summary card
// - FocusProgressRing: Circular countdown timer

import SwiftUI

// MARK: - Progress Indicator

struct ProgressIndicator: View {
    let completed: Int
    let total: Int
    let label: String?
    var color: Color = Tokens.Color.primary
    var showPercentage: Bool = false

    var progress: Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }

    var progressColor: Color {
        if progress >= 1.0 {
            return Tokens.Color.success
        }
        return color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            // Label + count
            HStack(spacing: Tokens.Spacing.base) {
                if let label = label {
                    Text(label)
                        .font(Tokens.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.appTextPrimary)
                }

                Spacer()

                // Count: "3 of 5"
                Text("\(completed) of \(total)")
                    .font(Tokens.Typography.label)
                    .foregroundColor(Color.appTextSecondary)

                // Percentage (optional)
                if showPercentage {
                    Text("(\(Int(progress * 100))%)")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextSecondary)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: Tokens.Border.radiusSmall)
                        .fill(Color.appBackgroundSecondary)

                    // Progress fill
                    RoundedRectangle(cornerRadius: Tokens.Border.radiusSmall)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * progress)
                        .animation(
                            .easeInOut(duration: 0.4),
                            value: progress
                        )
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Progress Summary

/// Daily progress card with energy context
struct ProgressSummary: View {
    let completedCount: Int
    let totalCount: Int
    let energyLevel: Int?  // 1–4
    var showCelebration: Bool = true

    var allDone: Bool {
        totalCount > 0 && completedCount >= totalCount
    }

    var energyColor: Color {
        switch energyLevel {
        case 1: return Tokens.Color.warning
        case 2: return Tokens.Color.warning
        case 3: return Tokens.Color.info
        case 4, 5: return Tokens.Color.success
        default: return Color.appTextSecondary
        }
    }

    var energyLabel: String {
        switch energyLevel {
        case 1: return "Survival"
        case 2: return "Low"
        case 3: return "Good"
        case 4: return "High"
        case 5: return "Very High"
        default: return "Unknown"
        }
    }

    var body: some View {
        AuDHDCard(spacing: Tokens.Spacing.base) {
            HStack(spacing: Tokens.Spacing.base) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    // Title
                    Text("Today's Progress")
                        .font(Tokens.Typography.h3)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.appTextPrimary)

                    // Stats
                    HStack(spacing: Tokens.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                            Text("\(completedCount)")
                                .font(Tokens.Typography.h2)
                                .fontWeight(.bold)
                                .foregroundColor(Tokens.Color.success)

                            Text("complete")
                                .font(Tokens.Typography.caption)
                                .foregroundColor(Color.appTextSecondary)
                        }

                        Divider()
                            .frame(height: 32)

                        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                            Text("\(totalCount - completedCount)")
                                .font(Tokens.Typography.h2)
                                .fontWeight(.bold)
                                .foregroundColor(Color.appTextPrimary)

                            Text("to go")
                                .font(Tokens.Typography.caption)
                                .foregroundColor(Color.appTextSecondary)
                        }

                        Spacer()

                        // Energy indicator (if available)
                        if let energyLevel = energyLevel {
                            VStack(alignment: .trailing, spacing: Tokens.Spacing.xs) {
                                HStack(spacing: 2) {
                                    ForEach(1...4, id: \.self) { pip in
                                        Circle()
                                            .fill(pip <= energyLevel ? energyColor : Color.appBorder)
                                            .frame(width: 6, height: 6)
                                    }
                                }

                                Text(energyLabel)
                                    .font(Tokens.Typography.caption)
                                    .foregroundColor(energyColor)
                            }
                        }
                    }
                }

                Spacer()

                // Celebration emoji (if all done)
                if allDone && showCelebration {
                    Text("🎉")
                        .font(.system(size: 32))
                }
            }
        }
    }
}

// MARK: - Progress Ring (Circular Timer)

struct ProgressRing: View {
    let progress: Double  // 0.0 to 1.0
    let totalMinutes: Int
    let label: String
    var isUrgent: Bool = false  // Last 2 min
    var size: CGFloat = 220

    var timeRemaining: (minutes: Int, seconds: Int) {
        let totalSeconds = Int(Double(totalMinutes * 60) * (1.0 - progress))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return (minutes, seconds)
    }

    var ringColor: Color {
        isUrgent ? Tokens.Color.warning : Tokens.Color.primary
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(
                    Color.appBackgroundSecondary,
                    lineWidth: 16
                )

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(
                        lineWidth: 16,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    .linear(duration: 1),
                    value: progress
                )

            // Center content
            VStack(spacing: Tokens.Spacing.sm) {
                Text("\(timeRemaining.minutes):\(String(format: "%02d", timeRemaining.seconds))")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(isUrgent ? Tokens.Color.warning : Color.appTextPrimary)

                Text(label)
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Color.appTextSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Energy Check-In Card

struct EnergyCheckInCard: View {
    @Binding var selectedLevel: Int
    var onChanged: (() -> Void)? = nil

    let energyLevels: [(level: Int, label: String, color: Color)] = [
        (1, "Survival", Tokens.Color.warning),
        (2, "Low", Tokens.Color.warning),
        (3, "Good", Tokens.Color.info),
        (4, "High", Tokens.Color.success),
    ]

    var body: some View {
        AuDHDCard(spacing: Tokens.Spacing.base) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.base) {
                Text("How's your energy?")
                    .font(Tokens.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.appTextPrimary)

                HStack(spacing: Tokens.Spacing.md) {
                    ForEach(energyLevels, id: \.level) { level, label, color in
                        VStack(spacing: Tokens.Spacing.xs) {
                            Button(action: {
                                selectedLevel = level
                                onChanged?()
                            }) {
                                VStack(spacing: 2) {
                                    HStack(spacing: 2) {
                                        ForEach(1...level, id: \.self) { _ in
                                            Circle()
                                                .fill(color)
                                                .frame(width: 4, height: 4)
                                        }
                                    }
                                }
                                .frame(height: 24)
                                .frame(maxWidth: .infinity)
                                .padding(Tokens.Spacing.base)
                                .background(
                                    selectedLevel == level
                                        ? color.opacity(0.15)
                                        : Color.appBackgroundSecondary
                                )
                                .cornerRadius(Tokens.Border.radiusSmall)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Tokens.Border.radiusSmall)
                                        .strokeBorder(
                                            selectedLevel == level ? color : Color.appBorder,
                                            lineWidth: selectedLevel == level ? Tokens.Border.widthBold : Tokens.Border.widthDefault
                                        )
                                )
                            }
                            .buttonStyle(.plain)

                            Text(label)
                                .font(Tokens.Typography.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(Color.appTextSecondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Loading State

struct SkeletonLoader: View {
    var count: Int = 3
    var height: CGFloat = 60

    var body: some View {
        VStack(spacing: Tokens.Spacing.lg) {
            ForEach(0..<count, id: \.self) { _ in
                AuDHDCard {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                        RoundedRectangle(cornerRadius: Tokens.Border.radiusSmall)
                            .fill(Color.appBackgroundSecondary)
                            .frame(height: 16)
                            .frame(maxWidth: 150)

                        RoundedRectangle(cornerRadius: Tokens.Border.radiusSmall)
                            .fill(Color.appBackgroundSecondary)
                            .frame(height: 12)
                            .frame(maxWidth: 200)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: Tokens.Spacing.xl) {
            // Progress Indicator
            ProgressIndicator(
                completed: 3,
                total: 5,
                label: "Today's Tasks",
                color: Tokens.Color.primary,
                showPercentage: true
            )

            // Progress Summary
            ProgressSummary(
                completedCount: 2,
                totalCount: 5,
                energyLevel: 3
            )

            // Energy Check-In
            EnergyCheckInCard(selectedLevel: .constant(3))

            // Progress Ring
            VStack(spacing: Tokens.Spacing.base) {
                Text("Focus Session")
                    .font(Tokens.Typography.h3)

                ProgressRing(
                    progress: 0.4,
                    totalMinutes: 25,
                    label: "remaining",
                    size: 220
                )

                ProgressRing(
                    progress: 0.95,
                    totalMinutes: 25,
                    label: "remaining (urgent)",
                    isUrgent: true,
                    size: 200
                )
            }
            .padding()

            // Skeleton loader
            SkeletonLoader(count: 2)
        }
        .padding(Tokens.Spacing.lg)
    }
    .background(Color.appBackground)
}
