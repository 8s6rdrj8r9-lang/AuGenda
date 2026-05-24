// BlockView.swift
// AUDHD Agenda App
//
// Block system UI + BlockManager logic
// - Startup block auto-surfaces on first launch
// - Manual block selection and activation
// - Bundle auto-prompt and manual attachment
// - WeatherKit suggestions for outdoor blocks

import Combine
import SwiftUI
import SwiftData
import CoreLocation
import WeatherKit

// MARK: - BlockManager

@MainActor
final class BlockManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    nonisolated let objectWillChange = ObservableObjectPublisher()

    static let shared = BlockManager()

    @Published var currentBlock: Block? = nil
    @Published var weatherSuggestions: [WeatherSuggestion] = []
    @Published var isLoadingWeather: Bool = false
    @Published var autoBundlesToPrompt: [BundleTemplate] = []
    @Published var showBundlePrompt: Bool = false

    var modelContext: ModelContext?

    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
    private var lastKnownLocation: CLLocation? = nil

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - Start a block

    func startBlock(_ block: Block) {
        // Deactivate any currently active block
        if let current = currentBlock {
            current.isActive = false
            current.updatedAt = .now
        }

        block.isActive = true
        block.startedAt = .now
        block.updatedAt = .now
        currentBlock = block

        try? modelContext?.save()

        // Check weather if outdoor block
        if block.type.isOutdoor && block.weatherCheckEnabled {
            fetchWeatherSuggestions()
        } else {
            weatherSuggestions = []
        }

        // Find bundles to auto-prompt
        checkAutoBundles(for: block)
    }

    // MARK: - Complete a block

    func completeBlock(_ block: Block) {
        block.isActive = false
        block.isComplete ? () : ()
        block.completedAt = .now
        block.lastCompletedDate = .now
        block.updatedAt = .now
        updateStreak(for: block)

        // Reset all tasks for next run
        block.tasks?.forEach { task in
            task.isComplete = false
            task.completedAt = nil
        }

        // Remove attached bundles
        block.attachedBundles?.forEach { modelContext?.delete($0) }

        if currentBlock?.clientID == block.clientID {
            currentBlock = nil
        }

        try? modelContext?.save()
        weatherSuggestions = []
    }

    // MARK: - Attach a bundle to a block

    func attachBundle(template: BundleTemplate, to block: Block) {
        let attached = AttachedBundle.from(template: template)
        attached.block = block
        modelContext?.insert(attached)

        if block.attachedBundles == nil {
            block.attachedBundles = [attached]
        } else {
            block.attachedBundles?.append(attached)
        }

        try? modelContext?.save()
    }

    // MARK: - Streak tracking

    private func updateStreak(for block: Block) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        if let lastDate = block.lastStreakDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            switch daysBetween {
            case 0:
                break // completed twice today — don't double-count
            case 1:
                block.currentStreak += 1 // consecutive day
            default:
                block.currentStreak = 1  // streak broken
            }
        } else {
            block.currentStreak = 1
        }

        block.longestStreak = max(block.longestStreak, block.currentStreak)
        block.lastStreakDate = .now
    }

    // MARK: - Bundle auto-prompt check

    private func checkAutoBundles(for block: Block) {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<BundleTemplate>()
        let allTemplates = (try? context.fetch(descriptor)) ?? []

        let alreadyAttachedNames = Set(block.attachedBundles?.map { $0.name } ?? [])

        autoBundlesToPrompt = allTemplates.filter { template in
            !alreadyAttachedNames.contains(template.displayName) &&
            template.autoPromptBlockTypes.contains(block.type)
        }

        if !autoBundlesToPrompt.isEmpty {
            showBundlePrompt = true
        }
    }

    // MARK: - Weather

    func fetchWeatherSuggestions() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        isLoadingWeather = true

        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            isLoadingWeather = false
        }
    }

    private func fetchWeather(for location: CLLocation) {
        Swift.Task {
            do {
                let weather = try await weatherService.weather(for: location)
                let suggestions = buildSuggestions(from: weather)
                await MainActor.run {
                    self.weatherSuggestions = suggestions
                    self.isLoadingWeather = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingWeather = false
                    print("Weather fetch error: \(error)")
                }
            }
        }
    }

    private func buildSuggestions(from weather: Weather) -> [WeatherSuggestion] {
        var suggestions: [WeatherSuggestion] = []
        let current = weather.currentWeather
        let temp = current.temperature.converted(to: .celsius).value
        let condition = current.condition

        // Coat
        if temp < 10 {
            suggestions.append(WeatherSuggestion(
                item: "Heavy coat",
                reason: "It's \(Int(temp))°C out",
                icon: "thermometer.snowflake"
            ))
        } else if temp < 16 {
            suggestions.append(WeatherSuggestion(
                item: "Light jacket",
                reason: "It's \(Int(temp))°C — a bit cool",
                icon: "thermometer.medium"
            ))
        }

        // Umbrella / rain gear
        switch condition {
        case .rain, .heavyRain, .drizzle, .freezingRain:
            suggestions.append(WeatherSuggestion(
                item: "Umbrella",
                reason: "Rain expected",
                icon: "umbrella.fill"
            ))
        case .snow, .heavySnow, .blizzard, .blowingSnow:
            suggestions.append(WeatherSuggestion(
                item: "Snow boots + warm layers",
                reason: "Snow conditions",
                icon: "snowflake"
            ))
        case .sleet, .wintryMix, .freezingDrizzle:
            suggestions.append(WeatherSuggestion(
                item: "Umbrella + waterproof boots",
                reason: "Wintry mix expected",
                icon: "cloud.sleet.fill"
            ))
        default:
            break
        }

        // Wind
        let windSpeed = current.wind.speed.converted(to: .kilometersPerHour).value
        if windSpeed > 40 {
            suggestions.append(WeatherSuggestion(
                item: "Windbreaker",
                reason: "Wind at \(Int(windSpeed)) km/h",
                icon: "wind"
            ))
        }

        // Sun
        let uvIndex = current.uvIndex.value
        if uvIndex >= 3 {
            suggestions.append(WeatherSuggestion(
                item: "Sunscreen + sunglasses",
                reason: "UV index \(uvIndex)",
                icon: "sun.max.fill"
            ))
        }

        // Extra water reminder for hot days
        if temp > 24 {
            suggestions.append(WeatherSuggestion(
                item: "Extra water",
                reason: "It's \(Int(temp))°C — stay hydrated",
                icon: "drop.fill"
            ))
        }

        return suggestions
    }

    // MARK: - Seed default blocks and bundles

    func seedDefaultsIfNeeded() {
        guard let context = modelContext else { return }

        let blockDescriptor = FetchDescriptor<Block>()
        let existingBlocks = (try? context.fetch(blockDescriptor)) ?? []
        guard existingBlocks.isEmpty else { return }

        // Create default blocks in order
        let blockTypes: [BlockType] = [
            .startup, .shutdown, .shop, .tech, .cleaning,
            .cooking, .maintenance, .family, .shopping, .adventures, .travel
        ]

        for (index, type) in blockTypes.enumerated() {
            let block = Block(type: type, sortOrder: index)
            block.weatherCheckEnabled = type.isOutdoor
            context.insert(block)

            // Add default tasks per block type
            let taskTitles = defaultTasks(for: type)
            for (taskIndex, title) in taskTitles.enumerated() {
                let task = BlockTask(title: title, sortOrder: taskIndex)
                task.block = block
                context.insert(task)
            }
        }

        // Create default bundle templates
        let bundleTypes: [BundleType] = [.dogBag, .snacks, .extraWater]
        for (index, type) in bundleTypes.enumerated() {
            let template = BundleTemplate(type: type)
            template.sortOrder = index
            context.insert(template)

            for (itemIndex, itemTitle) in type.defaultItems.enumerated() {
                let item = BundleTemplateItem(title: itemTitle, sortOrder: itemIndex)
                item.template = template
                context.insert(item)
            }
        }

        try? context.save()
    }

    private func defaultTasks(for type: BlockType) -> [String] {
        switch type {
        case .startup:
            return [
                "Morning meds",
                "Drink water",
                "Check agenda",
                "Breakfast",
                "Get dressed"
            ]
        case .shutdown:
            return [
                "Evening meds",
                "Review tomorrow's agenda",
                "Tidy common areas",
                "Charge devices",
                "Wind down routine"
            ]
        case .cleaning:
            return [
                "Dishes",
                "Wipe surfaces",
                "Vacuum",
                "Take out trash if needed"
            ]
        case .cooking:
            return [
                "Check recipe",
                "Gather ingredients",
                "Prep workspace",
                "Cook",
                "Clean as you go"
            ]
        case .shopping:
            return [
                "Check shopping list",
                "Reusable bags packed",
                "Check wallet + cards",
                "Phone charged"
            ]
        case .adventures:
            return [
                "Check destination",
                "Phone charged",
                "Keys",
                "Wallet"
            ]
        case .travel:
            return [
                "Documents ready",
                "Phone + charger packed",
                "Confirm booking",
                "Keys to trusted person if needed"
            ]
        case .tech:
            return [
                "Check task list",
                "Close distracting apps",
                "Set focus session"
            ]
        case .maintenance:
            return [
                "Identify what needs doing",
                "Gather tools",
                "Complete task",
                "Clean up"
            ]
        case .family:
            return [
                "Check in with household",
                "Any shared tasks today?"
            ]
        case .shop:
            return [
                "List ready",
                "Payment method",
                "Bags"
            ]
        case .custom:
            return []
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Swift.Task { @MainActor in
            self.lastKnownLocation = location
            self.fetchWeather(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Swift.Task { @MainActor in
            self.isLoadingWeather = false
            print("Location error: \(error)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Swift.Task { @MainActor in
            let isAuthorized: Bool
            #if os(iOS)
            isAuthorized = manager.authorizationStatus == .authorizedWhenInUse ||
                           manager.authorizationStatus == .authorizedAlways
            #else
            isAuthorized = manager.authorizationStatus == .authorizedAlways
            #endif
            if isAuthorized {
                manager.requestLocation()
            }
        }
    }
}


// MARK: - Block List View

struct BlockListView: View {

    @EnvironmentObject private var blockManager: BlockManager
    @Query(sort: \Block.sortOrder) private var blocks: [Block]
    @State private var showingBlock: Block? = nil

    // Auto-surface startup block
    private var startupBlock: Block? {
        blocks.first { $0.type == .startup && $0.shouldAutoSurface }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {

                    // Startup auto-surface banner
                    if let startup = startupBlock, blockManager.currentBlock == nil {
                        StartupBannerView(block: startup) {
                            blockManager.startBlock(startup)
                            showingBlock = startup
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    // Active block card
                    if let active = blockManager.currentBlock {
                        ActiveBlockCard(block: active) {
                            showingBlock = active
                        }
                        .padding(.horizontal)
                    }

                    // Block grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(blocks) { block in
                            BlockGridCell(block: block) {
                                blockManager.startBlock(block)
                                showingBlock = block
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Blocks")
            .sheet(item: $showingBlock) { block in
                BlockDetailView(block: block)
                    .environmentObject(blockManager)
            }
        }
    }
}


// MARK: - Startup Banner

struct StartupBannerView: View {
    let block: Block
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sunrise.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Start your day")
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("\(block.totalTaskCount) tasks ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if block.currentStreak > 1 {
                        Text("🔥 \(block.currentStreak) day streak")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Button("Begin") {
                onStart()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(14)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        )
    }
}


// MARK: - Active Block Card

struct ActiveBlockCard: View {
    let block: Block
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: block.icon)
                    .font(.title2)
                    .foregroundStyle(Color.appAccent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(block.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(block.completedTaskCount) of \(block.totalTaskCount) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: block.totalTaskCount > 0
                            ? Double(block.completedTaskCount) / Double(block.totalTaskCount)
                            : 0)
                        .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 32, height: 32)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.appAccent.opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Block Grid Cell

struct BlockGridCell: View {
    let block: Block
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: block.icon)
                    .font(.title2)
                    .foregroundStyle(block.isActive ? Color.appAccent : .secondary)

                Text(block.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                if block.isActive {
                    Text("\(block.completedTaskCount)/\(block.totalTaskCount)")
                        .font(.caption2)
                        .foregroundStyle(Color.appAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                block.isActive
                    ? Color.appAccent.opacity(0.1)
                    : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        block.isActive ? Color.appAccent.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Block Detail View

struct BlockDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blockManager: BlockManager

    let block: Block

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // Weather suggestions
                    if !blockManager.weatherSuggestions.isEmpty {
                        WeatherSuggestionsCard(suggestions: blockManager.weatherSuggestions)
                            .padding(.horizontal)
                    }

                    if blockManager.isLoadingWeather {
                        HStack {
                            ProgressView()
                            Text("Checking weather…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }

                    // Bundle prompt
                    if blockManager.showBundlePrompt && !blockManager.autoBundlesToPrompt.isEmpty {
                        BundlePromptCard(
                            templates: blockManager.autoBundlesToPrompt,
                            block: block
                        )
                        .padding(.horizontal)
                    }

                    // Attached bundles
                    if let bundles = block.attachedBundles, !bundles.isEmpty {
                        ForEach(bundles) { bundle in
                            AttachedBundleCard(bundle: bundle)
                                .padding(.horizontal)
                        }
                    }

                    // Block tasks
                    VStack(spacing: 8) {
                        ForEach(block.tasks?.sorted { $0.sortOrder < $1.sortOrder } ?? []) { task in
                            BlockTaskRow(task: task)
                        }
                    }
                    .padding(.horizontal)

                    // Complete block button
                    if block.isComplete {
                        Button {
                            blockManager.completeBlock(block)
                            dismiss()
                        } label: {
                            Label("Complete Block", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(block.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .navigationBarTrailing
                    #else
                    return .primaryAction
                    #endif
                }()) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .navigationBarLeading
                    #else
                    return .automatic
                    #endif
                }()) {
                    // Manual bundle add
                    Menu {
                        BundleMenuItems(block: block)
                    } label: {
                        Label("Add Bundle", systemImage: "plus.circle")
                    }
                }
            }
        }
    }
}


// MARK: - Block Task Row

struct BlockTaskRow: View {

    @Environment(\.modelContext) private var modelContext
    let task: BlockTask

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    task.isComplete.toggle()
                    task.completedAt = task.isComplete ? .now : nil
                }
                try? modelContext.save()
            } label: {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isComplete ? Color.appAccent : .secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.body)
                .strikethrough(task.isComplete)
                .foregroundStyle(task.isComplete ? .secondary : .primary)

            Spacer()

            if task.isOptional {
                Text("optional")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}


// MARK: - Weather Suggestions Card

struct WeatherSuggestionsCard: View {
    let suggestions: [WeatherSuggestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Weather check", systemImage: "cloud.sun.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            ForEach(suggestions, id: \.item) { suggestion in
                HStack(spacing: 10) {
                    Image(systemName: suggestion.icon)
                        .foregroundStyle(.cyan)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.item)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(suggestion.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.cyan.opacity(0.3), lineWidth: 1)
        )
    }
}


// MARK: - Bundle Prompt Card

struct BundlePromptCard: View {

    @EnvironmentObject private var blockManager: BlockManager
    let templates: [BundleTemplate]
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Suggested bundles", systemImage: "shippingbox.fill")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(templates) { template in
                HStack {
                    Image(systemName: template.icon)
                        .foregroundStyle(Color.appAccent)
                    Text(template.displayName)
                        .font(.subheadline)
                    Spacer()
                    Button("Add") {
                        blockManager.attachBundle(template: template, to: block)
                        blockManager.autoBundlesToPrompt.removeAll {
                            $0.clientID == template.clientID
                        }
                        if blockManager.autoBundlesToPrompt.isEmpty {
                            blockManager.showBundlePrompt = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.appAccent)
                    .controlSize(.small)
                }
            }

            Button("Skip all") {
                blockManager.showBundlePrompt = false
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.appAccent.opacity(0.3), lineWidth: 1)
        )
    }
}


// MARK: - Attached Bundle Card

struct AttachedBundleCard: View {

    @Environment(\.modelContext) private var modelContext
    let bundle: AttachedBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(bundle.name, systemImage: bundle.icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(bundle.completedItemCount)/\(bundle.totalItemCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(bundle.items?.sorted { $0.sortOrder < $1.sortOrder } ?? []) { item in
                HStack(spacing: 10) {
                    Button {
                        item.isComplete.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isComplete ? Color.appAccent : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text(item.title)
                        .font(.subheadline)
                        .strikethrough(item.isComplete)
                        .foregroundStyle(item.isComplete ? .secondary : .primary)

                    Spacer()
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}


// MARK: - Bundle Menu Items (for manual add)

struct BundleMenuItems: View {

    @EnvironmentObject private var blockManager: BlockManager
    @Query private var templates: [BundleTemplate]
    let block: Block

    var body: some View {
        let attached = Set(block.attachedBundles?.map { $0.name } ?? [])
        ForEach(templates) { template in
            if !attached.contains(template.displayName) {
                Button {
                    blockManager.attachBundle(template: template, to: block)
                } label: {
                    Label(template.displayName, systemImage: template.icon)
                }
            }
        }
    }
}
