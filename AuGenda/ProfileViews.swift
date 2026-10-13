// ProfileViews.swift
// AUDHD Agenda App
//
// Profile creation (3-step setup), household switcher, per-profile settings.
// Covers: 1) setup flow  2) quick-switch  3) profile settings  4) neurotype editor

import SwiftUI
import SwiftData
import Contacts
#if os(iOS)
import ContactsUI
import UIKit
#endif

// MARK: - Color(hex:)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - ProfileRole display

extension ProfileRole {
    var displayName: String {
        switch self {
        case .coordinator: return "Coordinator"
        case .adult:       return "Adult"
        case .child:       return "Child"
        }
    }
    var tagline: String {
        switch self {
        case .coordinator: return "Household admin — full visibility, assign to anyone"
        case .adult:       return "Can assign tasks to any profile including children"
        case .child:       return "Simplified view — sees their own tasks only"
        }
    }
    var icon: String {
        switch self {
        case .coordinator: return "star.fill"
        case .adult:       return "person.fill"
        case .child:       return "figure.child"
        }
    }
}

// MARK: - Supporting enum display names

extension FrictionLabel {
    var displayName: String {
        switch self {
        case .friction: return "Friction level"
        case .effort:   return "Effort level"
        case .energy:   return "Energy cost"
        }
    }
}

extension TaskLanguageStyle {
    var displayName: String {
        switch self {
        case .standard:   return "Standard (direct)"
        case .choiceOnly: return "Choice-framed (PDA)"
        case .simple:     return "Simple language"
        }
    }
}

extension NotificationStyle {
    var displayName: String {
        switch self {
        case .standard:    return "Standard"
        case .predictable: return "Predictable (consistent timing)"
        case .minimal:     return "Minimal (as few as possible)"
        }
    }
}

// MARK: - ProfileAvatarView

/// Reusable avatar — shows contact/Memoji image if available, else colour + initials.
struct ProfileAvatarView: View {

    let profile: Profile
    var size: CGFloat = 36
    var showRing: Bool = false

    var body: some View {
        ZStack {
            #if os(iOS)
            if let data = profile.avatarImageData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(hex: profile.avatarColorHex))
                    .frame(width: size, height: size)
                Text(profile.initials.isEmpty ? "?" : profile.initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            #else
            Circle()
                .fill(Color(hex: profile.avatarColorHex))
                .frame(width: size, height: size)
            Text(profile.initials.isEmpty ? "?" : profile.initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            #endif
        }
        .overlay(
            Circle()
                .strokeBorder(Color.appAccent, lineWidth: showRing ? 2.5 : 0)
                .padding(-1.5)
        )
    }
}

// MARK: - ProfileQuickSwitchButton
// Toolbar button — shows active avatar, opens the full switcher sheet.

struct ProfileQuickSwitchButton: View {

    @EnvironmentObject private var profileManager: ActiveProfileManager
    @State private var showSwitcher = false

    var body: some View {
        Button {
            showSwitcher = true
        } label: {
            if let profile = profileManager.activeProfile {
                ProfileAvatarView(profile: profile, size: 32, showRing: false)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showSwitcher) {
            ProfileSwitcherSheet(isPresented: $showSwitcher)
                .presentationDetents([.medium])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
        }
    }
}

// MARK: - ProfileSwitcherSheet

struct ProfileSwitcherSheet: View {

    @Binding var isPresented: Bool
    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]
    @State private var showAddProfile = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Profile grid
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 80), spacing: 16)],
                    spacing: 20
                ) {
                    ForEach(profiles) { profile in
                        Button {
                            withAnimation(.spring(duration: 0.25)) {
                                profileManager.switchTo(profile)
                            }
                            isPresented = false
                        } label: {
                            VStack(spacing: 8) {
                                ProfileAvatarView(
                                    profile: profile,
                                    size: 64,
                                    showRing: profileManager.activeProfile?.clientID == profile.clientID
                                )
                                VStack(spacing: 2) {
                                    Text(profile.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Text(profile.role.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Add profile button
                    Button {
                        showAddProfile = true
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.secondary.opacity(0.12))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Add")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)

                Spacer()
            }
            .navigationTitle("Switch profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .sheet(isPresented: $showAddProfile) {
            ProfileSetupView(isPresented: $showAddProfile)
                .presentationDetents([.large])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
        }
    }
}

// MARK: - ProfileSetupView
// 3-step sheet: name + role → neurotypes → avatar.

struct ProfileSetupView: View {

    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]

    /// True when shown as the first-launch onboarding — no cancel, dismiss disabled.
    var isOnboarding: Bool = false

    /// Capacity choice parked by `CognitiveStateSelector` when it ran before
    /// us. Drives two things:
    ///   1. Minimal-mode rendering (Survival/Low → name-only screen)
    ///   2. Carrying the density pin onto the new profile's preferences
    @AppStorage("firstLaunch.pendingDensityRaw") private var pendingDensityRaw: String = ""

    private var pendingMode: DensityMode? {
        DensityMode(rawValue: pendingDensityRaw)
    }

    /// Survival or Low capacity users get a single-screen "what should we
    /// call you" form, with everything else defaulted. Functional/High see
    /// the full 3-step Name → Neurotypes → Avatar flow.
    private var minimalMode: Bool {
        guard isOnboarding, let mode = pendingMode else { return false }
        return mode == .survival || mode == .low
    }

    @State private var step = 0
    @State private var name = ""
    @State private var selectedRole: ProfileRole = .adult
    @State private var selectedNeurotypes: Set<Neurotype> = []
    @State private var avatarImageData: Data? = nil
    @State private var avatarColorHex = ProfileSetupView.avatarColors[0]
    @State private var showContactPicker = false

    private var isFirstProfile: Bool { profiles.isEmpty }

    var body: some View {
        if minimalMode {
            minimalBody
        } else {
            fullBody
        }
    }

    // MARK: - Minimal body (Survival / Low first-launch)
    //
    // One screen, one decision: a name. Everything else gets defaulted
    // (AuDHD neurotype preset, coordinator role for the first profile,
    // a randomized avatar color). Onboarding doesn't follow this path
    // either — the user said they're overwhelmed; we honour that.

    private var minimalBody: some View {
        // Empty name → Done is disabled AND visibly muted. SwiftUI's
        // default disabled style on toolbar buttons can be too subtle
        // (just a small opacity drop), so we hammer it manually.
        let nameEmpty = name.trimmingCharacters(in: .whitespaces).isEmpty

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Just one thing")
                            .font(.caption).fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text("What should we call you?")
                            .font(.largeTitle).fontWeight(.bold)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("First name or nickname", text: $name)
                            .font(.title3)
                            .padding(14)
                            .background(
                                Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .submitLabel(.done)
                            .onSubmit { if !name.isEmpty { saveProfile() } }
                    }

                    Text("Everything else is set to a reasonable default. You can change neurotypes, avatar, and more from Settings whenever you have capacity.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Soft warm dawn — carries the warm-ember tone from the
            // CognitiveStateSelector survival button into the next screen,
            // so the emotional through-line of "you're held here" persists
            // past the overwhelm gate. Fades to transparent by mid-screen
            // so the form has a calm neutral base to sit on.
            .scrollContentBackground(.hidden)
            .background {
                LinearGradient(
                    colors: [
                        Color.warmEmber.opacity(0.22),
                        Color.warmEmber.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Welcome")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveProfile() }
                        .fontWeight(.semibold)
                        .foregroundStyle(nameEmpty ? Color.secondary : Color.appAccent)
                        .opacity(nameEmpty ? 0.45 : 1.0)
                        .disabled(nameEmpty)
                        .accessibilityHint(nameEmpty ? "Type a name to enable" : "")
                }
            }
        }
        .interactiveDismissDisabled(isOnboarding)
        .onAppear { if profiles.isEmpty { selectedRole = .coordinator } }
    }

    // MARK: - Full body (Functional / High, or non-onboarding)

    private var fullBody: some View {
        NavigationStack {
            VStack(spacing: 0) {

                ProgressView(value: Double(step + 1), total: 3)
                    .tint(Color.appAccent)
                    .padding(.horizontal)
                    .padding(.top, 8)

                TabView(selection: $step) {
                    stepName.tag(0)
                    stepNeurotypes.tag(1)
                    stepAvatar.tag(2)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
            }
            .navigationTitle(stepTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Cancel (non-onboarding only)
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresented = false }
                    }
                }
                // Back (step > 0)
                if step > 0 {
                    ToolbarItem(placement: {
                        #if os(iOS)
                        return .navigationBarLeading
                        #else
                        return .automatic
                        #endif
                    }()) {
                        Button {
                            withAnimation { step -= 1 }
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
                // Next / Done
                ToolbarItem(placement: .confirmationAction) {
                    if step < 2 {
                        Button("Next") { withAnimation { step += 1 } }
                            .disabled(step == 0 && name.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button("Done") { saveProfile() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showContactPicker) {
            ContactAvatarPicker(
                onSelect: { data in
                    avatarImageData = data
                    showContactPicker = false
                },
                onCancel: { showContactPicker = false }
            )
        }
        #endif
        .interactiveDismissDisabled(isOnboarding)
        .onAppear {
            if profiles.isEmpty { selectedRole = .coordinator }
        }
    }

    // MARK: Step 0 — Name & Role

    private var stepName: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                    TextField("First name or nickname", text: $name)
                        .font(.title3)
                        .padding(14)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .submitLabel(.next)
                        .onSubmit { if !name.isEmpty { withAnimation { step += 1 } } }
                }

                if isFirstProfile {
                    // First profile is always coordinator — not a picker
                    HStack(spacing: 12) {
                        Image(systemName: ProfileRole.coordinator.icon)
                            .foregroundStyle(Color.appAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Household Coordinator")
                                .fontWeight(.medium)
                            Text("First profile is the coordinator — you can add others next.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Role in the household")
                            .font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                        ForEach([ProfileRole.adult, .child], id: \.self) { role in
                            roleCard(role)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func roleCard(_ role: ProfileRole) -> some View {
        Button { selectedRole = role } label: {
            HStack(spacing: 14) {
                Image(systemName: role.icon)
                    .font(.title3)
                    .foregroundStyle(selectedRole == role ? Color.appAccent : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.displayName).fontWeight(.medium).foregroundStyle(.primary)
                    Text(role.tagline).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selectedRole == role ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedRole == role ? Color.appAccent : .secondary)
            }
            .padding(14)
            .background(
                selectedRole == role ? Color.appAccent.opacity(0.1) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 1 — Neurotypes

    private var stepNeurotypes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Select everything that fits. You can change this any time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ForEach(Neurotype.allCases) { neurotype in
                    Button { toggleNeurotype(neurotype) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: neurotype.icon)
                                .font(.title3)
                                .foregroundStyle(
                                    selectedNeurotypes.contains(neurotype) ? Color.appAccent : .secondary
                                )
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(neurotype.displayName)
                                    .fontWeight(.medium).foregroundStyle(.primary)
                                Text(neurotype.tagline)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: selectedNeurotypes.contains(neurotype)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    selectedNeurotypes.contains(neurotype) ? Color.appAccent : .secondary
                                )
                        }
                        .padding(14)
                        .background(
                            selectedNeurotypes.contains(neurotype)
                                ? Color.appAccent.opacity(0.1) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private func toggleNeurotype(_ neurotype: Neurotype) {
        if selectedNeurotypes.contains(neurotype) {
            selectedNeurotypes.remove(neurotype)
        } else {
            if neurotype == .neurotypical {
                selectedNeurotypes.removeAll()
            } else {
                selectedNeurotypes.remove(.neurotypical)
            }
            selectedNeurotypes.insert(neurotype)
        }
    }

    // MARK: Step 2 — Avatar

    private var stepAvatar: some View {
        ScrollView {
            VStack(spacing: 28) {

                // Live preview
                SetupAvatarPreview(
                    imageData: avatarImageData,
                    colorHex: avatarColorHex,
                    initials: initialsFromName
                )

                VStack(spacing: 12) {
                    #if os(iOS)
                    Button {
                        showContactPicker = true
                    } label: {
                        Label("Use your Memoji or contact photo", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    #endif

                    if avatarImageData != nil {
                        Button("Remove photo") {
                            withAnimation { avatarImageData = nil }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Or choose a colour")
                        .font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(
                        columns: Array(repeating: .init(.flexible()), count: 8),
                        spacing: 12
                    ) {
                        ForEach(ProfileSetupView.avatarColors, id: \.self) { hex in
                            Button {
                                withAnimation { avatarColorHex = hex; avatarImageData = nil }
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle().strokeBorder(
                                            Color.white,
                                            lineWidth: avatarColorHex == hex && avatarImageData == nil ? 3 : 0
                                        )
                                    )
                                    .shadow(color: Color(hex: hex).opacity(0.4), radius: 3, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: Helpers

    private var stepTitle: String {
        switch step {
        case 0:  return isFirstProfile ? "Create your profile" : "New profile"
        case 1:  return "What fits?"
        case 2:  return "Your avatar"
        default: return ""
        }
    }

    private var initialsFromName: String {
        name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined().uppercased()
    }

    static let avatarColors = [
        "#5AC8FA", "#BF5AF2", "#30D158",
        "#FF9F0A", "#FF375F", "#0A84FF",
        "#FFD60A", "#5E5CE6"
    ]

    // MARK: Save

    private func saveProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // In minimal mode, neurotypes haven't been picked yet — default to the
        // AuDHD preset (the app's namesake) since this user came in via the
        // overwhelm gate. They can adjust from Settings later.
        let effectiveNeurotypes: [Neurotype]
        if minimalMode {
            effectiveNeurotypes = [.adhd, .autism]
        } else {
            effectiveNeurotypes = Array(selectedNeurotypes)
        }

        // Minimal mode: also randomize the avatar color so two minimal-mode
        // setups don't all land on the same blue.
        let effectiveColorHex = minimalMode
            ? ProfileSetupView.avatarColors.randomElement() ?? avatarColorHex
            : avatarColorHex

        let existingCount = (try? modelContext.fetch(FetchDescriptor<Profile>()))?.count ?? 0

        let profile = Profile(
            name: trimmedName,
            role: minimalMode && profiles.isEmpty ? .coordinator : selectedRole,
            neurotypes: effectiveNeurotypes,
            sortOrder: existingCount
        )
        profile.avatarImageData = avatarImageData
        profile.avatarColorHex = effectiveColorHex

        // Build preferences. Filter out .neurotypical from the preset key
        // since it's a no-op selection (no ND-specific defaults).
        let filtered = Set(effectiveNeurotypes).subtracting([.neurotypical])
        let prefs = filtered.isEmpty
            ? ProfilePreferences()
            : ProfilePreferences.makePreset(for: Array(filtered))

        // Apply the capacity choice that CognitiveStateSelector parked
        // before this view ran. Single source of truth: the @AppStorage
        // key. Clear it after consumption so a later return through this
        // flow (unlikely but possible) doesn't pick up a stale value.
        // Option A: the parked capacity choice becomes ENERGY, not a pin.
        // First launch should not silently pin every new profile forever —
        // the density picker is the only pinning surface.
        if let mode = pendingMode {
            prefs.currentEnergyLevel = mode.representativeEnergyLevel
        }

        profile.preferences = prefs
        modelContext.insert(profile)
        modelContext.insert(prefs)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
            return
        }

        pendingDensityRaw = ""
        profileManager.switchTo(profile)
        isPresented = false
    }

}

// MARK: - SetupAvatarPreview (private, used only in setup step 2)

private struct SetupAvatarPreview: View {
    let imageData: Data?
    let colorHex: String
    let initials: String

    var body: some View {
        ZStack {
            #if os(iOS)
            if let data = imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: colorHex)
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            #else
            Color(hex: colorHex)
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            #endif
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
        .shadow(radius: 10, y: 4)
        .animation(.spring(duration: 0.3), value: colorHex)
        .animation(.spring(duration: 0.3), value: imageData != nil)
    }
}

// MARK: - ContactAvatarPicker

#if os(iOS)
/// Wraps CNContactPickerViewController. No explicit permission prompt needed —
/// the system picker handles access internally.
struct ContactAvatarPicker: UIViewControllerRepresentable {

    var onSelect: (Data) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        // Only show contacts that have an avatar set
        picker.predicateForEnablingContact = NSPredicate(format: "imageDataAvailable == YES")
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, onCancel: onCancel) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (Data) -> Void
        let onCancel: () -> Void

        init(onSelect: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard let data = contact.imageData else { return }
            onSelect(data)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
#endif

// MARK: - ProfileSettingsView

struct ProfileSettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Bindable var prefs: ProfilePreferences
    let profile: Profile

    @State private var showNeurotypeEditor = false
    @State private var showResetConfirm = false
    @State private var showCapacitySelector = false
    @State private var checkInFrequency = CognitiveCheckInTracker.frequency
    @State private var dailyRolling24h = CognitiveCheckInTracker.dailyUsesRollingWindow

    var body: some View {
        Form {

            // Profile header
            Section {
                HStack(spacing: 14) {
                    ProfileAvatarView(profile: profile, size: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                            .font(.title3).fontWeight(.semibold)
                        HStack(spacing: 6) {
                            Image(systemName: profile.role.icon)
                                .font(.caption)
                            Text(profile.role.displayName)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Neurotypes
            Section {
                if profile.neurotypes.isEmpty {
                    Text("None selected").foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(profile.neurotypes) { neurotype in
                            Label(neurotype.displayName, systemImage: neurotype.icon)
                                .font(.caption).fontWeight(.medium)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.appAccent.opacity(0.12), in: Capsule())
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button("Edit neurotypes") { showNeurotypeEditor = true }
                    .foregroundStyle(.primary)
            } header: { Text("Neurotypes") }

            // Font
            Section {
                ForEach(AppFont.allCases) { font in
                    Button {
                        prefs.appFont = font
                        save()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(font.displayName).foregroundStyle(.primary)
                                Text(font.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if prefs.appFont == font {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: { Text("Font") }

            // Energy & EF
            Section {
                // Set capacity — opens the same picker that runs on first
                // launch. Surfaces the current pin / auto-derived mode and
                // lets the user re-commit at any moment.
                Button {
                    showCapacitySelector = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(Color.appAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set capacity")
                                .foregroundStyle(.primary)
                            Text(currentCapacityLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Picker("Capacity check-ins", selection: $checkInFrequency) {
                    ForEach(CognitiveCheckInFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }
                .onChange(of: checkInFrequency) { _, _ in
                    CognitiveCheckInTracker.frequency = checkInFrequency
                }

                // Only meaningful for the daily mode: choose whether "once
                // daily" means the first use of each calendar day, or a full
                // 24 hours since the last check-in.
                if checkInFrequency == .daily {
                    Toggle(isOn: $dailyRolling24h) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Space check-ins 24h apart")
                            Text(dailyRolling24h
                                 ? "Re-asks 24 hours after your last check-in."
                                 : "Re-asks the first time you open the app each day.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color.appAccent)
                    .onChange(of: dailyRolling24h) { _, _ in
                        CognitiveCheckInTracker.dailyUsesRollingWindow = dailyRolling24h
                    }
                }

                Toggle("Energy check-ins", isOn: $prefs.energyTrackingEnabled)
                    .tint(Color.appAccent)
                    .onChange(of: prefs.energyTrackingEnabled) { _, _ in save() }

                if prefs.energyTrackingEnabled {
                    Stepper(
                        "Low EF threshold: friction ≤ \(prefs.lowEFMaxFriction)",
                        value: $prefs.lowEFMaxFriction, in: 1...4
                    )
                    .onChange(of: prefs.lowEFMaxFriction) { _, _ in save() }
                }

                Toggle("Hyperfocus guard", isOn: $prefs.hyperfocusGuard)
                    .tint(Color.appAccent)
                    .onChange(of: prefs.hyperfocusGuard) { _, _ in save() }

                Toggle("Show check-in nudges", isOn: $prefs.showCheckInNudges)
                    .tint(Color.appAccent)
                    .onChange(of: prefs.showCheckInNudges) { _, _ in save() }
            } header: {
                Text("Energy & Executive Function")
            } footer: {
                if prefs.hyperfocusGuard {
                    Text("Sessions end at the configured time with no extension option.")
                }
            }

            // Language & framing
            Section {
                Picker(prefs.frictionLabel.displayName, selection: $prefs.frictionLabelRaw) {
                    ForEach(FrictionLabel.allCases, id: \.rawValue) { label in
                        Text(label.displayName).tag(label.rawValue)
                    }
                }
                .onChange(of: prefs.frictionLabelRaw) { _, _ in save() }

                Picker("Task framing", selection: $prefs.taskLanguageStyleRaw) {
                    ForEach(TaskLanguageStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .onChange(of: prefs.taskLanguageStyleRaw) { _, _ in save() }

                Toggle("Show deadline pressure", isOn: $prefs.deadlinePressureVisible)
                    .tint(Color.appAccent)
                    .onChange(of: prefs.deadlinePressureVisible) { _, _ in save() }
            } header: { Text("Language & framing") }

            // Focus sessions
            Section {
                Stepper(
                    "Session: \(prefs.focusSessionMinutes) min",
                    value: $prefs.focusSessionMinutes, in: 10...90, step: 5
                )
                .onChange(of: prefs.focusSessionMinutes) { _, _ in save() }

                Stepper(
                    "Break: \(prefs.breakMinutes) min",
                    value: $prefs.breakMinutes, in: 5...30, step: 5
                )
                .onChange(of: prefs.breakMinutes) { _, _ in save() }
            } header: { Text("Focus sessions") }

            // Transitions & time
            Section {
                Toggle("Routine protection", isOn: $prefs.routineProtectionEnabled)
                    .tint(Color.appAccent)
                    .onChange(of: prefs.routineProtectionEnabled) { _, _ in save() }

                Stepper(
                    "Transition prep: \(prefs.transitionPrepMinutes) min",
                    value: $prefs.transitionPrepMinutes, in: 0...30, step: 5
                )
                .onChange(of: prefs.transitionPrepMinutes) { _, _ in save() }

                Toggle("Time blindness warnings", isOn: $prefs.timeBlindnessWarningsEnabled)
                    .tint(Color.appAccent)
                    .onChange(of: prefs.timeBlindnessWarningsEnabled) { _, _ in save() }
            } header: { Text("Transitions & time") }

            // Notifications
            Section {
                Picker("Notification style", selection: $prefs.notificationStyleRaw) {
                    ForEach(NotificationStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .onChange(of: prefs.notificationStyleRaw) { _, _ in save() }
            } header: { Text("Notifications") }

            // Display
            Section {
                Toggle("Larger controls", isOn: $prefs.largeTouchTargets)
                    .tint(Color.appAccent)
                    .onChange(of: prefs.largeTouchTargets) { _, _ in save() }

                Toggle("Increase contrast", isOn: $prefs.highContrastMode)
                    .tint(Color.appAccent)
                    .onChange(of: prefs.highContrastMode) { _, _ in save() }

                Toggle("Low stimulation mode", isOn: $prefs.lowStimulationMode)
                    .tint(Color.appAccent)
                    .onChange(of: prefs.lowStimulationMode) { _, _ in save() }

                Toggle(
                    "Sensory context suggestions",
                    isOn: $prefs.sensoryContextTagsEnabled
                )
                .tint(Color.appAccent)
                .onChange(of: prefs.sensoryContextTagsEnabled) { _, _ in save() }

                Toggle("Reduce motion", isOn: $prefs.reduceMotion)
                    .tint(Color.appAccent)
                    .onChange(of: prefs.reduceMotion) { _, _ in save() }
                Text("Text size follows Dynamic Type. Profile display options combine with device accessibility settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Display")
            } footer: {
                Text("Low stimulation reduces animation, shadows, and information density. Sensory context suggestions add quick tags when editing tasks.")
            }

            // Reset
            if !prefs.appliedPresetRaw.isEmpty {
                Section {
                    Button(role: .destructive) { showResetConfirm = true } label: {
                        Label("Reset to neurotype defaults", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Restores all settings to the preset generated from your neurotypes.")
                }
            }
        }
        .navigationTitle("\(profile.name)'s Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showNeurotypeEditor) {
            NeurotypeEditorSheet(profile: profile, isPresented: $showNeurotypeEditor) {
                // Re-stamp the preset key so "Reset" uses updated neurotypes
                let updated = profile.neurotypes.filter { $0 != .neurotypical }
                if !updated.isEmpty {
                    prefs.appliedPresetRaw = updated.map { $0.rawValue }.joined(separator: ",")
                }
                save()
            }
        }
        .sheet(isPresented: $showCapacitySelector) {
            CognitiveStateSelector(
                isPresented: $showCapacitySelector,
                isFirstLaunch: false
            )
        }
        .confirmationDialog(
            "Reset to neurotype defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { prefs.resetToPreset(); save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite your current settings with your neurotype defaults.")
        }
    }

    /// Subtitle for the "Set capacity" row — shows what the user is at
    /// right now: their pinned mode if set, otherwise the auto-derived one.
    private var currentCapacityLabel: String {
        if let pinned = prefs.densityPinned {
            return "Pinned to \(pinned.label)"
        }
        let derived = DensityMode.autoFrom(energyLevel: prefs.currentEnergyLevel)
        return "Currently \(derived.label) — auto from energy"
    }

    private func save() {
        prefs.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
    }
}

// MARK: - NeurotypeEditorSheet

private struct NeurotypeEditorSheet: View {

    let profile: Profile
    @Binding var isPresented: Bool
    var onSave: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selected: Set<Neurotype>

    init(profile: Profile, isPresented: Binding<Bool>, onSave: @escaping () -> Void) {
        self.profile = profile
        self._isPresented = isPresented
        self.onSave = onSave
        self._selected = State(initialValue: Set(profile.neurotypes))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Neurotype.allCases) { neurotype in
                        Button {
                            if selected.contains(neurotype) {
                                selected.remove(neurotype)
                            } else {
                                if neurotype == .neurotypical { selected.removeAll() }
                                else { selected.remove(.neurotypical) }
                                selected.insert(neurotype)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: neurotype.icon)
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(neurotype) ? Color.appAccent : .secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(neurotype.displayName).fontWeight(.medium).foregroundStyle(.primary)
                                    Text(neurotype.tagline).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: selected.contains(neurotype) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(neurotype) ? Color.appAccent : .secondary)
                            }
                            .padding(14)
                            .background(
                                selected.contains(neurotype)
                                    ? Color.appAccent.opacity(0.1) : Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Neurotypes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.neurotypes = Array(selected)
                        profile.updatedAt = .now
                        do {
                            try modelContext.save()
                        } catch {
                            modelContext.rollback()
                            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
                            return
                        }
                        onSave()
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
    }
}

// MARK: - FlowLayout
// Wrapping horizontal layout for neurotype chips in ProfileSettingsView.

struct FlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
