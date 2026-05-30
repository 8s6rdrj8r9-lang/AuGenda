//
//  AuGendaWatchWidgets.swift
//  AuGendaWatchWidgets
//
//  AuGenda Now — the watch's primary surface. Spec §4: "Treat complications
//  as the primary product, not an afterthought." This single widget supports
//  the four watchOS accessory families and feeds the Smart Stack.
//

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline entry

struct NowEntry: TimelineEntry {
    let date: Date

    /// Current task title shown as NOW. nil = "nothing scheduled" calm state.
    let nowTitle: String?
    /// When the current task is scheduled — used for "Now" vs "in 12 min" hint.
    let nowScheduledDate: Date?
    /// Friction (1-5) for the muted accent tint resolver.
    let nowFrictionLevel: Int
    /// Free-text context tag for the tint resolver + caption.
    let nowContextTag: String

    /// Next task title — surfaced only when density allows it.
    let nextTitle: String?

    /// Density derived from the user's energy / pinned mode. The complication
    /// in Survival mode collapses NEXT to a count, matching the in-app rules.
    let density: DensityMode

    /// Smart Stack relevance — see TimelineProvider.relevance(for:).
    let relevance: TimelineEntryRelevance?

    static var placeholder: NowEntry {
        // Spec §4: "Provide a calm redacted/placeholder state."
        NowEntry(
            date: .now,
            nowTitle: nil,
            nowScheduledDate: nil,
            nowFrictionLevel: 2,
            nowContextTag: "",
            nextTitle: nil,
            density: .survival,
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
            relevance: TimelineEntryRelevance(score: 0.8)
        )
    }
}

// MARK: - Timeline provider

struct NowTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> NowEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NowEntry) -> Void) {
        let entry = context.isPreview ? NowEntry.preview : buildEntry()
        completion(entry)
    }

    /// Spec §4 + §15: sparse timeline, never poll. We pre-render the now and
    /// (at most) the next two transitions, then ask the system to refresh
    /// only on next state change — pushed from the watch app via
    /// `WidgetCenter.shared.reloadAllTimelines()` on meaningful change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NowEntry>) -> Void) {
        let current = buildEntry()
        var entries: [NowEntry] = [current]

        // Pre-render the rollover at the scheduled time so the widget
        // updates without polling.
        if let scheduled = current.nowScheduledDate, scheduled > .now {
            entries.append(buildEntry(at: scheduled))
        }

        let policy: TimelineReloadPolicy = .never
        completion(Timeline(entries: entries, policy: policy))
    }

    // MARK: - Data fetch

    /// Build an entry from the watch's own SwiftData store. Falls back to
    /// the calm placeholder when the store is empty / unreachable — the
    /// widget never shows "loading" (Spec §4).
    private func buildEntry(at date: Date = .now) -> NowEntry {
        guard let nowItem = fetchNextActionable(after: date) else {
            return NowEntry(
                date: date,
                nowTitle: nil,
                nowScheduledDate: nil,
                nowFrictionLevel: 2,
                nowContextTag: "",
                nextTitle: nil,
                density: .survival,
                relevance: TimelineEntryRelevance(score: 0.1)
            )
        }

        let next = fetchNextActionable(after: date, excluding: nowItem.clientID)
        let energyLevel = fetchEnergyLevel() ?? 3

        return NowEntry(
            date: date,
            nowTitle: nowItem.title,
            nowScheduledDate: nowItem.isAllDay ? nil : nowItem.scheduledDate,
            nowFrictionLevel: nowItem.frictionLevel,
            nowContextTag: nowItem.contextTag,
            nextTitle: next?.title,
            density: DensityMode.autoFrom(energyLevel: energyLevel),
            relevance: relevance(for: nowItem, at: date)
        )
    }

    private func fetchNextActionable(after date: Date, excluding excludeID: UUID? = nil) -> AgendaItem? {
        do {
            let context = ModelContext(WatchAppContainer.production)
            var descriptor = FetchDescriptor<AgendaItem>(
                predicate: #Predicate<AgendaItem> { !$0.isComplete },
                sortBy: [SortDescriptor(\.scheduledDate)]
            )
            descriptor.fetchLimit = 5
            let items = try context.fetch(descriptor)
            return items.first(where: { item in
                if let snooze = item.snoozedUntil, snooze > date { return false }
                if let excludeID, item.clientID == excludeID { return false }
                return true
            })
        } catch {
            return nil
        }
    }

    private func fetchEnergyLevel() -> Int? {
        do {
            let context = ModelContext(WatchAppContainer.production)
            let descriptor = FetchDescriptor<Profile>()
            let profile = try context.fetch(descriptor).first
            return profile?.preferences?.currentEnergyLevel
        } catch {
            return nil
        }
    }

    /// Spec §4: Smart Stack relevance. Score rises as the scheduled time
    /// approaches, drops back after. Very simple v1 model — enough to make
    /// the Smart Stack surface the widget near the relevant moment without
    /// being noisy throughout the day.
    private func relevance(for item: AgendaItem, at date: Date) -> TimelineEntryRelevance {
        guard !item.isAllDay else { return TimelineEntryRelevance(score: 0.3) }
        let delta = item.scheduledDate.timeIntervalSince(date)
        if delta < 0 { return TimelineEntryRelevance(score: 0.9, duration: 30 * 60) }
        if delta < 15 * 60 { return TimelineEntryRelevance(score: 0.95, duration: 30 * 60) }
        if delta < 60 * 60 { return TimelineEntryRelevance(score: 0.7) }
        return TimelineEntryRelevance(score: 0.3)
    }
}

// MARK: - Entry view

struct NowEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: NowEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangularBody
            case .accessoryCircular:    circularBody
            case .accessoryCorner:      cornerBody
            case .accessoryInline:      inlineBody
            default:                    rectangularBody
            }
        }
        // Spec §9, §10: true-black, decolored ambient (AOD) handled by
        // widgetRenderingMode → .accented automatically dimming colors.
        .containerBackground(WatchTokens.Color.background, for: .widget)
    }

    private var tint: Color {
        WatchTint.resolve(frictionLevel: entry.nowFrictionLevel, contextTag: entry.nowContextTag)
    }

    // MARK: Rectangular

    private var rectangularBody: some View {
        HStack(alignment: .top, spacing: WatchTokens.Spacing.sm) {
            RoundedRectangle(cornerRadius: WatchTokens.Border.leadingBar / 2)
                .fill(tint)
                .frame(width: WatchTokens.Border.leadingBar)
                .frame(maxHeight: .infinity)
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.nowTitle ?? "Nothing scheduled")
                    .font(WatchTokens.Typography.nextTitle)
                    .foregroundStyle(WatchTokens.Color.textPrimary)
                    .lineLimit(2)

                if let next = entry.nextTitle, entry.density.watchShowsNext {
                    Text("Next · \(next)")
                        .font(WatchTokens.Typography.metadata)
                        .foregroundStyle(WatchTokens.Color.textSecondary)
                        .lineLimit(1)
                }

                if let date = entry.nowScheduledDate {
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
        let now = entry.nowTitle ?? "Nothing scheduled"
        if let next = entry.nextTitle, entry.density.watchShowsNext {
            return "Now, \(now). Next, \(next)."
        }
        return "Now, \(now)."
    }

    // MARK: Circular

    private var circularBody: some View {
        ZStack {
            // Ring (not fill) — spec §10 "accent tint only".
            Circle()
                .strokeBorder(tint, lineWidth: 2)
                .widgetAccentable()
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WatchTokens.Color.textPrimary)
        }
        .accessibilityLabel(entry.nowTitle.map { "Current task: \($0)" } ?? "Nothing scheduled")
    }

    private var glyph: String {
        if entry.nowTitle == nil { return "moon" }
        if entry.nowContextTag.contains("focus") { return "scope" }
        if entry.nowContextTag.contains("phone") { return "phone" }
        if entry.nowContextTag.contains("email") { return "envelope" }
        return "circle"
    }

    // MARK: Corner

    private var cornerBody: some View {
        Image(systemName: glyph)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .widgetAccentable()
            .widgetLabel {
                Text(entry.nowTitle ?? "Open")
                    .lineLimit(1)
            }
            .accessibilityLabel(entry.nowTitle.map { "Current task: \($0)" } ?? "Open AuGenda")
    }

    // MARK: Inline

    private var inlineBody: some View {
        let text = entry.nowTitle.map { "Now · \($0)" } ?? "Nothing scheduled"
        return Text(text)
            .widgetAccentable()
            .accessibilityLabel(entry.nowTitle.map { "Now, \($0)" } ?? "Nothing scheduled")
    }
}

// MARK: - Widget configuration

struct AuGendaWatchWidgets: Widget {
    let kind: String = "AuGendaNowWidget"

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
        // Smart Stack relevance — entry-level scores drive the timing.
    }
}

// MARK: - Preview

#Preview(as: .accessoryRectangular) {
    AuGendaWatchWidgets()
} timeline: {
    NowEntry.preview
    NowEntry.placeholder
}
