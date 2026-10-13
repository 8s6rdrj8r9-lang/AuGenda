// AuGendaWatchWidgets.swift
// AuGenda Watch complication

import SwiftUI
import WidgetKit

enum NowEntrySyncState {
    case current
    case empty
    case unavailable
}

struct NowEntry: TimelineEntry {
    let date: Date
    let nowTitle: String?
    let nowScheduledDate: Date?
    let nowFrictionLevel: Int
    let nowContextTag: String
    let nextTitle: String?
    let density: DensityMode
    let syncState: NowEntrySyncState
    let relevance: TimelineEntryRelevance?

    static var placeholder: NowEntry {
        NowEntry(
            date: .now,
            nowTitle: nil,
            nowScheduledDate: nil,
            nowFrictionLevel: 2,
            nowContextTag: "",
            nextTitle: nil,
            density: .survival,
            syncState: .unavailable,
            relevance: nil
        )
    }

    static var preview: NowEntry {
        NowEntry(
            date: .now,
            nowTitle: "Morning meds",
            nowScheduledDate: Date.now.addingTimeInterval(900),
            nowFrictionLevel: 2,
            nowContextTag: "home",
            nextTitle: "Review agenda",
            density: .functional,
            syncState: .current,
            relevance: TimelineEntryRelevance(score: 0.8)
        )
    }
}

struct NowTimelineProvider: TimelineProvider {
    private let store = WatchSharedStateStore()

    func placeholder(in context: Context) -> NowEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NowEntry) -> Void) {
        let now = Date.now
        completion(
            context.isPreview
                ? .preview
                : buildEntry(at: now, snapshot: store.presentationSnapshot(at: now))
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowEntry>) -> Void) {
        let now = Date.now
        guard let rawSnapshot = store.loadSnapshot(),
              let snapshot = store.presentationSnapshot(from: rawSnapshot, at: now) else {
            completion(
                Timeline(
                    entries: [buildEntry(at: now, snapshot: nil)],
                    policy: .after(now.addingTimeInterval(15 * 60))
                )
            )
            return
        }

        // Bound the timeline: current state, at most two task rollovers, and
        // a freshness-expiry entry that redacts titles if no new snapshot arrives.
        let futureTransitions = snapshot.agendaItems
            .filter { $0.scheduledDate > now }
            .map(\.scheduledDate)
            .sorted()
            .prefix(2)

        var dates = [now]
        for date in futureTransitions where !dates.contains(date) {
            dates.append(date)
        }

        let freshnessExpiry = snapshot.generatedAt
            .addingTimeInterval(WatchSyncContract.snapshotMaxAge + 1)
        if freshnessExpiry > now, !dates.contains(freshnessExpiry) {
            dates.append(freshnessExpiry)
        }
        dates.sort()

        let entries = dates.map {
            buildEntry(
                at: $0,
                snapshot: store.presentationSnapshot(from: rawSnapshot, at: $0)
            )
        }
        let reloadDate = max(
            now.addingTimeInterval(15 * 60),
            freshnessExpiry.addingTimeInterval(5 * 60)
        )
        completion(Timeline(entries: entries, policy: .after(reloadDate)))
    }

    func buildEntry(at date: Date, snapshot: WatchSnapshot?) -> NowEntry {
        guard let snapshot,
              snapshot.profileID != nil,
              snapshot.isFresh(at: date) else {
            return NowEntry(
                date: date,
                nowTitle: nil,
                nowScheduledDate: nil,
                nowFrictionLevel: 2,
                nowContextTag: "",
                nextTitle: nil,
                density: .survival,
                syncState: .unavailable,
                relevance: TimelineEntryRelevance(score: 0.05)
            )
        }

        let actionable = snapshot.agendaItems
            .filter { item in
                guard let snoozedUntil = item.snoozedUntil else { return true }
                return snoozedUntil <= date
            }
            .sorted { $0.scheduledDate < $1.scheduledDate }

        guard !actionable.isEmpty else {
            return NowEntry(
                date: date,
                nowTitle: nil,
                nowScheduledDate: nil,
                nowFrictionLevel: 2,
                nowContextTag: "",
                nextTitle: snapshot.backlogTasks.first?.title,
                density: resolvedDensity(snapshot),
                syncState: .empty,
                relevance: TimelineEntryRelevance(score: 0.1)
            )
        }

        // Before the first scheduled item, show that first item. Once time
        // crosses a later scheduled date, advance to that item exactly once.
        let currentIndex = actionable.lastIndex(where: { $0.scheduledDate <= date }) ?? 0
        let current = actionable[currentIndex]
        let next = actionable.indices.contains(currentIndex + 1)
            ? actionable[currentIndex + 1].title
            : snapshot.backlogTasks.first?.title

        return NowEntry(
            date: date,
            nowTitle: current.title,
            nowScheduledDate: current.isAllDay ? nil : current.scheduledDate,
            nowFrictionLevel: current.frictionLevel,
            nowContextTag: current.contextTag,
            nextTitle: next,
            density: resolvedDensity(snapshot),
            syncState: .current,
            relevance: relevance(for: current, at: date)
        )
    }

    private func resolvedDensity(_ snapshot: WatchSnapshot) -> DensityMode {
        if let raw = snapshot.densityModeRaw,
           let pinned = DensityMode(rawValue: raw) {
            return pinned
        }
        return .autoFrom(energyLevel: snapshot.currentEnergyLevel)
    }

    private func relevance(
        for item: WatchAgendaSummary,
        at date: Date
    ) -> TimelineEntryRelevance {
        guard !item.isAllDay else { return TimelineEntryRelevance(score: 0.3) }
        let delta = item.scheduledDate.timeIntervalSince(date)
        if delta < 0 { return TimelineEntryRelevance(score: 0.9, duration: 30 * 60) }
        if delta < 15 * 60 { return TimelineEntryRelevance(score: 0.95, duration: 30 * 60) }
        if delta < 60 * 60 { return TimelineEntryRelevance(score: 0.7) }
        return TimelineEntryRelevance(score: 0.3)
    }
}

struct NowEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangularBody
            case .accessoryCircular: circularBody
            case .accessoryCorner: cornerBody
            case .accessoryInline: inlineBody
            default: rectangularBody
            }
        }
        .containerBackground(WatchTokens.Color.background, for: .widget)
    }

    private var tint: Color {
        WatchTint.resolve(
            frictionLevel: entry.nowFrictionLevel,
            contextTag: entry.nowContextTag
        )
    }

    private var primaryLabel: String {
        switch entry.syncState {
        case .current: return entry.nowTitle ?? "Nothing scheduled"
        case .empty: return "Nothing scheduled"
        case .unavailable: return "Open AuGenda to sync"
        }
    }

    private var rectangularBody: some View {
        HStack(alignment: .top, spacing: WatchTokens.Spacing.sm) {
            RoundedRectangle(cornerRadius: WatchTokens.Border.leadingBar / 2)
                .fill(entry.syncState == .unavailable ? Color.gray : tint)
                .frame(width: WatchTokens.Border.leadingBar)
                .frame(maxHeight: .infinity)
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 0) {
                Text(primaryLabel)
                    .font(WatchTokens.Typography.nextTitle)
                    .foregroundStyle(WatchTokens.Color.textPrimary)
                    .lineLimit(2)

                if entry.syncState != .unavailable,
                   let next = entry.nextTitle,
                   entry.density.watchShowsNext {
                    Text("Next · \(next)")
                        .font(WatchTokens.Typography.metadata)
                        .foregroundStyle(WatchTokens.Color.textSecondary)
                        .lineLimit(1)
                }

                if entry.syncState == .current,
                   let date = entry.nowScheduledDate {
                    Text(date, style: .relative)
                        .font(WatchTokens.Typography.metadata)
                        .foregroundStyle(WatchTokens.Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rectangularAccessibilityLabel)
    }

    private var rectangularAccessibilityLabel: String {
        if entry.syncState == .unavailable {
            return "AuGenda needs a fresh sync. Open AuGenda on iPhone."
        }
        if let next = entry.nextTitle, entry.density.watchShowsNext {
            return "Now, \(primaryLabel). Next, \(next)."
        }
        return "Now, \(primaryLabel)."
    }

    private var circularBody: some View {
        ZStack {
            Circle()
                .strokeBorder(entry.syncState == .unavailable ? Color.gray : tint, lineWidth: 2)
                .widgetAccentable()
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WatchTokens.Color.textPrimary)
        }
        .accessibilityLabel(primaryLabel)
    }

    private var glyph: String {
        if entry.syncState == .unavailable { return "arrow.triangle.2.circlepath" }
        if entry.nowTitle == nil { return "moon" }
        if entry.nowContextTag.contains("focus") { return "scope" }
        if entry.nowContextTag.contains("phone") { return "phone" }
        if entry.nowContextTag.contains("email") { return "envelope" }
        return "circle"
    }

    private var cornerBody: some View {
        Image(systemName: glyph)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(entry.syncState == .unavailable ? Color.gray : tint)
            .widgetAccentable()
            .widgetLabel {
                Text(primaryLabel)
                    .lineLimit(1)
            }
            .accessibilityLabel(primaryLabel)
    }

    private var inlineBody: some View {
        Text(entry.syncState == .current ? "Now · \(primaryLabel)" : primaryLabel)
            .widgetAccentable()
            .accessibilityLabel(primaryLabel)
    }
}

struct AuGendaWatchWidgets: Widget {
    let kind = WatchSyncContract.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowTimelineProvider()) { entry in
            NowEntryView(entry: entry)
        }
        .configurationDisplayName("AuGenda Now")
        .description("Your current task and what's next.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}
