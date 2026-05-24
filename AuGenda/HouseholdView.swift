// HouseholdView.swift
// AUDHD Agenda App
//
// Coordinator-only overview of the whole household's day.
// Shows each profile's energy, progress, and today's items — all completable from here.
// Accessible via the person.3 toolbar button in TodayView when role == .coordinator.

import SwiftUI
import SwiftData

// MARK: - HouseholdOverviewView

struct HouseholdOverviewView: View {

    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]
    // Query all items — we need complete + incomplete for progress display
    @Query(sort: \AgendaItem.scheduledDate) private var allItems: [AgendaItem]

    @State private var addItemForProfile: Profile? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(profiles) { profile in
                    ProfileDayCard(
                        profile: profile,
                        items: todayItems(for: profile),
                        onAddItem: { addItemForProfile = profile }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Household")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .sheet(item: $addItemForProfile) { profile in
            AddAgendaItemView(
                isPresented: Binding(
                    get: { addItemForProfile != nil },
                    set: { if !$0 { addItemForProfile = nil } }
                ),
                preAssignedProfileID: profile.clientID
            )
            .presentationDetents([.large])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
        }
    }

    private func todayItems(for profile: Profile) -> [AgendaItem] {
        let endOfDay = Calendar.current.endOfDay(for: .now)
        let id = profile.clientID
        return allItems.filter { item in
            guard item.scheduledDate <= endOfDay else { return false }
            if let assigned = item.assignedToProfileID { return assigned == id }
            return false   // household view only shows explicitly assigned items
        }
    }
}

// MARK: - ProfileDayCard

struct ProfileDayCard: View {

    let profile: Profile
    let items: [AgendaItem]
    var onAddItem: () -> Void

    @State private var isExpanded = true

    private var incomplete: [AgendaItem] { items.filter { !$0.isComplete } }
    private var completedCount: Int { items.filter { $0.isComplete }.count }
    private var totalCount: Int { items.count }
    private var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Card header
            Button {
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    ProfileAvatarView(profile: profile, size: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(profile.name)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(profile.role.displayName)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            // Energy indicator
                            if let prefs = profile.preferences, prefs.energyTrackingEnabled {
                                EnergyPip(level: prefs.currentEnergyLevel)
                            }

                            // Progress text
                            if totalCount > 0 {
                                Text("\(completedCount) of \(totalCount) done")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Nothing assigned today")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // MARK: Progress bar
            if totalCount > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                        Rectangle()
                            .fill(progress >= 1 ? Color.green : Color.appAccent)
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(duration: 0.4), value: progress)
                    }
                }
                .frame(height: 2)
            }

            // MARK: Item list
            if isExpanded {
                VStack(spacing: 6) {
                    if incomplete.isEmpty {
                        HStack {
                            Image(systemName: totalCount > 0 ? "checkmark.circle.fill" : "tray")
                                .foregroundStyle(totalCount > 0 ? .green : .tertiary)
                            Text(totalCount > 0 ? "All done for today! 🎉" : "Nothing here yet")
                                .font(.subheadline)
                                .foregroundStyle(totalCount > 0 ? .green : .tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(incomplete) { item in
                            HouseholdItemRow(item: item, profileName: profile.name)
                        }
                    }

                    // Add item button
                    Button {
                        onAddItem()
                    } label: {
                        Label("Add item for \(profile.name)", systemImage: "plus")
                            .font(.caption)
                            .foregroundStyle(Color.appAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    progress >= 1 ? Color.green.opacity(0.4) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }
}

// MARK: - HouseholdItemRow

private struct HouseholdItemRow: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    #endif

    let item: AgendaItem
    let profileName: String

    var body: some View {
        HStack(spacing: 12) {
            Button { complete() } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text(item.scheduledDate.formatted(.dateTime.hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    FrictionDots(level: item.frictionLevel)

                    if !item.contextTag.isEmpty {
                        Text(item.contextTag)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func complete() {
        withAnimation(.spring(duration: 0.3)) {
            item.isComplete = true
            item.completedAt = .now
            item.updatedAt = .now
        }
        notificationManager.cancelNotifications(for: item)
        try? modelContext.save()
        #if canImport(WatchConnectivity)
        watchManager.sendSyncSnapshot()
        #endif
    }
}

// MARK: - EnergyPip
// Compact energy indicator for the household card header.

private struct EnergyPip: View {
    let level: Int

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        switch level {
        case 1, 2: return .orange
        case 3:    return .yellow
        default:   return .green
        }
    }

    private var label: String {
        switch level {
        case 1: return "Survival"
        case 2: return "Low"
        case 3: return "Moderate"
        case 4: return "Good"
        default: return "High"
        }
    }
}
