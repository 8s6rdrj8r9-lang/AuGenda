// OnboardingView.swift
// AuGenda
//
// First-launch orientation. Three calm cards explaining the few concepts
// that aren't self-evident from the dashboard:
//
//   1. Welcome  — what AuGenda is + privacy posture
//   2. Capacity — energy + density mode + tap the badge to pin
//   3. Capture  — brain dump vs detailed add
//
// Gated by an @AppStorage flag so it shows once and never again. Dismissal
// is always reachable (top-trailing close + final-page Get-started button)
// so no one can get trapped.

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    var onFinished: () -> Void = {}
    var onSkipped: () -> Void = {}

    @State private var page: Int = 0

    var body: some View {
        VStack(spacing: 0) {

            // Sticky top close — always reachable, never traps the user.
            HStack {
                Spacer()
                Button {
                    onSkipped()
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color.appTextSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip onboarding")
                .accessibilityHint("Closes the introduction")
            }
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.top, Tokens.Spacing.base)

            // Card carousel — Capacity is its own dedicated CognitiveStateSelector
            // sheet in the first-launch chain (and a Settings entry), so the
            // capacity card was removed from this surface to avoid duplicate copy.
            TabView(selection: $page) {
                welcomeCard.tag(0)
                captureCard.tag(1)
                checkInCard.tag(2)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            #endif

            // Footer — adaptive button based on page
            HStack {
                if page > 0 {
                    Button("Back") {
                        withAnimation { page -= 1 }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                if page < 2 {
                    Button("Next") {
                        withAnimation { page += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get started") {
                        onFinished()
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.vertical, Tokens.Spacing.lg)
        }
        .background(Color.appBackground)
    }

    // MARK: - Card 1: Welcome

    private var welcomeCard: some View {
        OnboardingCardLayout(
            icon: "sparkles",
            iconTint: Color.appAccent,
            title: "Welcome to AuGenda",
            paragraphs: [
                "An agenda app designed for ND brains — calm, glanceable, no demands.",
                "Your data stays on this device. AuGenda the company has no backend and can't see your tasks. Erase anytime from Settings → Privacy."
            ]
        )
    }

    // MARK: - Card 2: Capture

    private var captureCard: some View {
        OnboardingCardLayout(
            icon: "brain.head.profile",
            iconTint: Tokens.Color.primary,
            title: "Two ways to add tasks",
            paragraphs: [
                "Brain dump 🧠 — for the racing-thoughts moment. One thought per line, no friction levels or time estimates. Just type and save.",
                "Add task ➕ — when you have the energy to set friction, energy, time, context. Use this when planning.",
                "You can refine a brain-dumped task later if you want. Or never. Both are fine."
            ]
        )
    }

    // MARK: - Card 3: Capacity check-ins

    /// Interactive card — lets the user opt into the recurring "how are you?"
    /// check-in here, during onboarding. Off by default; whatever they pick
    /// is written straight to the tracker by CheckInFrequencyChooser. Wrapped
    /// in a ScrollView so the four options never clip on smaller devices.
    private var checkInCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(Color.warmEmber)

                Text("Capacity check-ins")
                    .font(Tokens.Typography.h1)
                    .foregroundColor(Color.appTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("AuGenda can ask “how are you?” when you open it, and match the view to your capacity. Off by default — pick what suits you. Change anytime in Settings.")
                    .font(Tokens.Typography.body)
                    .foregroundColor(Color.appTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                CheckInFrequencyChooser()
            }
            .padding(.horizontal, Tokens.Spacing.xl)
            .padding(.vertical, Tokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Reusable card layout

private struct OnboardingCardLayout: View {
    let icon: String
    let iconTint: Color
    let title: String
    let paragraphs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
            Spacer(minLength: 0)

            Image(systemName: icon)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(iconTint)

            Text(title)
                .font(Tokens.Typography.h1)
                .foregroundColor(Color.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Tokens.Spacing.base) {
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(Tokens.Typography.body)
                        .foregroundColor(Color.appTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
