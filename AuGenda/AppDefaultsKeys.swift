import Foundation

enum AppDefaultsKeys {
    static let resettable: Set<String> = Set([
        "activity.snoozes",
        "activity.completions",
        "energy.lastCheckIn",
        "irp.lastItemID",
        "irp.lastItemTitle",
        "irp.lastActiveDate",
        "irp.lastContextLabel",
        "interruptionContext.activity",
        "interruptionContext.itemID",
        "interruptionContext.timestamp",
        "density.advisor.dismissedUntilTS",
        "home.dashboard.useNewHome",
        "home.dashboard.density.pinned",
        "activeProfileID",
        "morningSetup.lastDate",
        "onboarding.completed",
        "onboarding.deferredForCapacity",
        "firstLaunch.pendingDensityRaw",
        "checkIn.preferenceOffered",
        "watch.sync.processedMutationIDs.v1",
        "ai.enabled",
        "ai.activeProvider",
        "ai.backupProvider",
        "ai.enableBackupFallback",
        "ai.autoEnrichNewTasks",
        "ai.showEnrichButtons",
        "ai.localOnlyMode",
        "ai.maxMonthlyCostUSD",
        "ai.ollama.host",
        "ai.ollama.model",
        "ai.deepseek.model",
        "ai.personalization.aboutMe",
        "ai.personalization.tone",
        "ai.personalization.allowInterestInference",
        "ai.personalization.memoryEnabled",
        "ai.personalization.memoryDepth",
        "cognitiveCheckIn.lastTimestamp",
        "cognitiveCheckIn.frequency",
        "cognitiveCheckIn.dailyRolling24h"
    ]).union(
        AIProvider.allCases.map { AIConsentPolicy.consentKey(for: $0) }
    ).union([AIConsentPolicy.ollamaDestinationKey])

    static func removeResettableValues(from defaults: UserDefaults = .standard) {
        for key in resettable {
            defaults.removeObject(forKey: key)
        }
    }
}
