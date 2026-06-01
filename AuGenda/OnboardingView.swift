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

    @State private var page: Int = 0

    var body: some View {
        VStack(spacing: 0) {

            // Sticky top close — always reachable, never traps the user.
            HStack {
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color.appTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip onboarding")
            }
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.top, Tokens.Spacing.base)

            // Card carousel
            TabView(selection: $page) {
                welcomeCard.tag(0)
                capacityCard.tag(1)
                captureCard.tag(2)
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
                "Your data syncs only via your own iCloud private database. AuGenda the company has no backend and can't see your tasks. Erase anytime from Settings → Privacy."
            ]
        )
    }

    // MARK: - Card 2: Capacity

    private var capacityCard: some View {
        OnboardingCardLayout(
            icon: "leaf",
            iconTint: Tokens.Color.success,
            title: "Tell it your capacity",
            paragraphs: [
                "Tap the energy pips at the top of the Today tab to set how you're feeling — Survival, Low, Functional, or High.",
                "The dashboard adapts: in Survival you see only the one thing to do; in High you see the whole picture. You can pin a mode if your energy doesn't match what you need to see."
            ]
        )
    }

    // MARK: - Card 3: Capture

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
