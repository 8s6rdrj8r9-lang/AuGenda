import Foundation
import Testing
@testable import AuGenda

@MainActor
struct AIEnrichmentTests {

    @Test func usageLedgerVersionedDateRoundTripPreservesFractionalSeconds() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000.654321)
        let entry = AIUsageEntry(
            provider: AIProvider.openai.rawValue,
            model: "test-model",
            promptTokens: 12,
            completionTokens: 8,
            estimatedCostUSD: 0.01,
            timestamp: timestamp
        )

        let data = try AIUsageLedger.encodePersistedEntries([entry])
        let decoded = try AIUsageLedger.decodePersistedEntries(data)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(decoded.needsMigration == false)
        #expect(object?["schemaVersion"] as? Int == AIUsageLedger.persistenceSchemaVersion)
        #expect(decoded.entries.count == 1)
        #expect(decoded.entries[0].timestamp == timestamp)
        #expect(decoded.entries[0].promptTokens == 12)

        struct LegacyEnvelope: Encodable {
            let schemaVersion: Int
            let entries: [AIUsageEntry]
        }
        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .iso8601
        let legacyData = try legacyEncoder.encode(
            LegacyEnvelope(schemaVersion: 1, entries: [entry])
        )
        let migrated = try AIUsageLedger.decodePersistedEntries(legacyData)
        #expect(migrated.needsMigration)
    }

    @Test func usageLedgerMigratesLegacyNumericDates() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 123_456)
        let entry = AIUsageEntry(
            provider: AIProvider.claude.rawValue,
            model: "legacy-model",
            promptTokens: 4,
            completionTokens: 2,
            estimatedCostUSD: 0.02,
            timestamp: timestamp
        )
        let legacyData = try JSONEncoder().encode([entry])

        let decoded = try AIUsageLedger.decodePersistedEntries(legacyData)

        #expect(decoded.needsMigration)
        #expect(decoded.entries[0].timestamp == timestamp)
    }

    @Test func usageLedgerMigratesBareISOEnvelopeAndQuarantinesCorruption() throws {
        let entry = AIUsageEntry(
            provider: AIProvider.openai.rawValue,
            model: "legacy-iso",
            promptTokens: 1,
            completionTokens: 1,
            estimatedCostUSD: 0,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bareISOData = try encoder.encode([entry])
        #expect(try AIUsageLedger.decodePersistedEntries(bareISOData).needsMigration)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuGenda-ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let corruptURL = directory.appendingPathComponent("ai-usage-ledger.json")
        try Data("not json".utf8).write(to: corruptURL)

        let quarantineURL = AIUsageLedger.quarantineCorruptFile(at: corruptURL)
        #expect(quarantineURL != nil)
        #expect(FileManager.default.fileExists(atPath: corruptURL.path) == false)
        #expect(
            quarantineURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
        )
        #expect(AIUsageLedger.removeQuarantinedFiles(in: directory))
        #expect(
            quarantineURL.map { FileManager.default.fileExists(atPath: $0.path) } == false
        )
    }

    @Test func configuredSpendCapFailsClosedForUntrustedLedger() {
        #expect(
            AIUsageLedger.spendAllowed(
                cap: 5,
                monthCost: 0,
                persistenceIsHealthy: false
            ) == false
        )
        #expect(
            AIUsageLedger.spendAllowed(
                cap: 5,
                monthCost: 4.99,
                persistenceIsHealthy: true
            )
        )
        #expect(
            AIUsageLedger.spendAllowed(
                cap: 5,
                monthCost: 5,
                persistenceIsHealthy: true
            ) == false
        )
    }

    @Test func quarantinedLedgerRemainsFailClosedAcrossLaunchesUntilRecovery() {
        let suiteName = "com.augenda.tests.ai-ledger-recovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Simulate launch one quarantining a corrupt primary.
        AIUsageLedger.setRecoveryRequired(true, defaults: defaults)
        #expect(AIUsageLedger.recoveryIsRequired(defaults: defaults))

        // Launch two sees no primary file, but the durable sentinel keeps a
        // configured spend cap closed instead of treating an empty ledger as $0.
        #expect(
            AIUsageLedger.spendAllowed(
                cap: 5,
                monthCost: 0,
                persistenceIsHealthy: !AIUsageLedger.recoveryIsRequired(
                    defaults: defaults
                )
            ) == false
        )

        AIUsageLedger.setRecoveryRequired(false, defaults: defaults)
        #expect(AIUsageLedger.recoveryIsRequired(defaults: defaults) == false)
    }

    @Test func personalizationMemoryDatesRoundTripAndMigrate() throws {
        let entry = PersonalizationContext.MemoryEntry(
            title: "Call pharmacy",
            band: DifficultyBand.moderate.rawValue,
            timestamp: Date(timeIntervalSince1970: 1_710_000_000.654321)
        )

        let isoData = try PersonalizationStore.encodePersistedMemory([entry])
        let isoDecoded = try PersonalizationStore.decodePersistedMemory(isoData)
        let object = try JSONSerialization.jsonObject(with: isoData) as? [String: Any]
        #expect(isoDecoded.needsMigration == false)
        #expect(
            object?["schemaVersion"] as? Int
                == PersonalizationStore.persistenceSchemaVersion
        )
        #expect(isoDecoded.entries[0].timestamp == entry.timestamp)

        struct LegacyEnvelope: Encodable {
            let schemaVersion: Int
            let entries: [PersonalizationContext.MemoryEntry]
        }
        let versionOneEncoder = JSONEncoder()
        versionOneEncoder.dateEncodingStrategy = .iso8601
        let versionOneData = try versionOneEncoder.encode(
            LegacyEnvelope(schemaVersion: 1, entries: [entry])
        )
        #expect(
            try PersonalizationStore.decodePersistedMemory(versionOneData)
                .needsMigration
        )

        let bareISOEncoder = JSONEncoder()
        bareISOEncoder.dateEncodingStrategy = .iso8601
        let bareISOData = try bareISOEncoder.encode([entry])
        #expect(try PersonalizationStore.decodePersistedMemory(bareISOData).needsMigration)

        let legacyData = try JSONEncoder().encode([entry])
        let legacyDecoded = try PersonalizationStore.decodePersistedMemory(legacyData)
        #expect(legacyDecoded.needsMigration)
        #expect(legacyDecoded.entries[0].title == entry.title)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuGenda-memory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let corruptURL = directory.appendingPathComponent("ai-personalization-memory.json")
        try Data("not json".utf8).write(to: corruptURL)
        let quarantineURL = PersonalizationStore.quarantineCorruptMemoryFile(at: corruptURL)
        #expect(quarantineURL != nil)
        #expect(FileManager.default.fileExists(atPath: corruptURL.path) == false)
        #expect(PersonalizationStore.removeQuarantinedMemoryFiles(in: directory))
        #expect(
            quarantineURL.map { FileManager.default.fileExists(atPath: $0.path) } == false
        )
    }

    @Test func configuredMemoryDepthMatchesPromptTransmission() {
        #expect(PersonalizationStore.normalizedMemoryDepth(0) == 1)
        #expect(PersonalizationStore.normalizedMemoryDepth(25) == 20)
        #expect(PersonalizationStore.normalizedAboutMe(String(repeating: "a", count: 5_000)).count == 4_000)

        let memory = (1...7).map {
            PersonalizationContext.MemoryEntry(
                title: "Task \($0)",
                band: DifficultyBand.easy.rawValue,
                timestamp: Date(timeIntervalSince1970: TimeInterval($0))
            )
        }
        let context = EnrichmentContext(
            rawTitle: "New task",
            userNote: nil,
            neurotypes: [],
            currentDensity: nil,
            personalization: PersonalizationContext(
                aboutMe: nil,
                tone: .calm,
                recentMemory: memory,
                allowInterestInference: false
            )
        )

        let message = EnrichmentPrompt.userMessage(for: context)
        #expect(message.contains("Task 1"))
        #expect(message.contains("Task 7"))
    }

    @Test func OllamaClassificationUsesExactPrivateRanges() {
        #expect(
            OllamaEndpointPolicy.classify("http://172.15.1.2:11434") == .remote
        )
        #expect(
            OllamaEndpointPolicy.classify("http://172.16.1.2:11434") == .privateNetwork
        )
        #expect(
            OllamaEndpointPolicy.classify("http://172.31.255.2:11434") == .privateNetwork
        )
        #expect(
            OllamaEndpointPolicy.classify("http://172.32.1.2:11434") == .remote
        )
        #expect(
            OllamaEndpointPolicy.classify("http://127.4.3.2:11434") == .loopback
        )
        #expect(
            OllamaEndpointPolicy.classify("http://010.0.0.1:11434") == .remote
        )
        #expect(
            OllamaEndpointPolicy.classify("https://fc.example.com:11434") == .remote
        )
        #expect(
            OllamaEndpointPolicy.classify("http://[fd12::1]:11434") == .privateNetwork
        )
        #expect(
            OllamaEndpointPolicy.classify("http://[::ffff:127.0.0.1]:11434") == .loopback
        )
        #expect(
            OllamaEndpointPolicy.classify("http://[::ffff:192.168.1.2]:11434")
                == .privateNetwork
        )
        #expect(
            OllamaEndpointPolicy.classify("http://[fc00:notvalid]:11434") == .invalid
        )
    }

    @Test func outboundPolicyBlocksCloudAndRemoteHostsInLocalOnlyMode() throws {
        let suiteName = "com.augenda.tests.ai-policy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "ai.enabled")
        defaults.set(true, forKey: "ai.localOnlyMode")

        #expect(throws: AIEnricherError.self) {
            try AIOutboundPolicy.enforce(provider: .openai, defaults: defaults)
        }

        defaults.set("https://example.com:11434", forKey: "ai.ollama.host")
        #expect(throws: AIEnricherError.self) {
            try AIOutboundPolicy.enforce(provider: .ollama, defaults: defaults)
        }

        defaults.set("http://192.168.1.10:11434", forKey: "ai.ollama.host")
        AIConsentPolicy.recordConsent(for: .ollama, defaults: defaults)
        #expect(throws: Never.self) {
            try AIOutboundPolicy.enforce(provider: .ollama, defaults: defaults)
        }
    }

    @Test func outboundPolicyEnforcesAIMasterFlag() {
        let suiteName = "com.augenda.tests.ai-master-flag.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "ai.enabled")
        AIConsentPolicy.recordConsent(for: .openai, defaults: defaults)
        #expect(throws: AIEnricherError.self) {
            try AIOutboundPolicy.enforce(provider: .openai, defaults: defaults)
        }

        defaults.set(true, forKey: "ai.enabled")
        #expect(throws: Never.self) {
            try AIOutboundPolicy.enforce(provider: .openai, defaults: defaults)
        }
    }

    @Test func providerConsentIsVersionedAndOllamaConsentIsDestinationSpecific() {
        let suiteName = "com.augenda.tests.ai-consent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "ai.enabled")

        #expect(throws: AIEnricherError.self) {
            try AIOutboundPolicy.enforce(provider: .openai, defaults: defaults)
        }
        AIConsentPolicy.recordConsent(for: .openai, defaults: defaults)
        #expect(throws: Never.self) {
            try AIOutboundPolicy.enforce(provider: .openai, defaults: defaults)
        }

        defaults.set("http://localhost:11434", forKey: "ai.ollama.host")
        AIConsentPolicy.recordConsent(for: .ollama, defaults: defaults)
        #expect(AIConsentPolicy.hasCurrentConsent(for: .ollama, defaults: defaults))

        defaults.set("https://ollama.example.com", forKey: "ai.ollama.host")
        #expect(
            AIConsentPolicy.hasCurrentConsent(for: .ollama, defaults: defaults) == false
        )
        #expect(throws: AIEnricherError.self) {
            try AIOutboundPolicy.enforce(provider: .ollama, defaults: defaults)
        }
        AIConsentPolicy.recordConsent(for: .ollama, defaults: defaults)
        #expect(throws: Never.self) {
            try AIOutboundPolicy.enforce(provider: .ollama, defaults: defaults)
        }
    }

    @Test func outboundPolicyBlocksUnencryptedRemoteOllamaEvenOutsideLocalOnly() {
        let suiteName = "com.augenda.tests.ai-transport.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "ai.enabled")
        defaults.set(false, forKey: "ai.localOnlyMode")
        defaults.set("http://example.com:11434", forKey: "ai.ollama.host")

        #expect(throws: AIEnricherError.self) {
            try AIOutboundPolicy.enforce(provider: .ollama, defaults: defaults)
        }
    }

    @Test func providerOutputIsValidatedBeforeUse() throws {
        var candidate = enrichment(
            title: "  Call pharmacy  ",
            friction: 2,
            interest: 5,
            confidence: 0.75
        )
        candidate.usage = TaskEnrichment.Usage(
            provider: AIProvider.openai.rawValue,
            model: "test-model",
            promptTokens: 10,
            completionTokens: 5
        )

        let validated = try EnrichmentResultValidator.validate(
            candidate,
            provider: .openai,
            allowInterest: false
        )

        #expect(validated.title == "Call pharmacy")
        #expect(validated.interest == nil)
        #expect(validated.friction == 2)
    }

    @Test func providerOutputRejectsOutOfRangeValues() {
        let candidate = enrichment(
            title: "Call pharmacy",
            friction: 99,
            interest: nil,
            confidence: 0.5
        )

        #expect(throws: AIEnricherError.self) {
            try EnrichmentResultValidator.validate(
                candidate,
                provider: .openai,
                allowInterest: false
            )
        }

        var excessiveUsage = enrichment(
            title: "Call pharmacy",
            friction: 2,
            interest: nil,
            confidence: 0.5
        )
        excessiveUsage.usage = TaskEnrichment.Usage(
            provider: AIProvider.openai.rawValue,
            model: "test-model",
            promptTokens: Int.max,
            completionTokens: 1
        )
        #expect(throws: AIEnricherError.self) {
            try EnrichmentResultValidator.validate(
                excessiveUsage,
                provider: .openai,
                allowInterest: false
            )
        }

        let missingUsage = enrichment(
            title: "Call pharmacy",
            friction: 2,
            interest: nil,
            confidence: 0.5
        )
        #expect(throws: AIEnricherError.self) {
            try EnrichmentResultValidator.validate(
                missingUsage,
                provider: .openai,
                allowInterest: false
            )
        }
    }

    @Test func providerOutputRejectsUnknownFieldsBlankTitlesAndUnsupportedContexts() throws {
        let unknownField = Data(
            #"{"title":"Call pharmacy","unexpected":true}"#.utf8
        )
        #expect(throws: AIEnricherError.self) {
            try EnrichmentPayloadDecoder.decode(unknownField)
        }

        let blankTitle = enrichment(
            title: "   ",
            friction: 2,
            interest: nil,
            confidence: 0.5
        )
        #expect(throws: AIEnricherError.self) {
            try EnrichmentResultValidator.validate(
                blankTitle,
                provider: .openai,
                allowInterest: false
            )
        }

        var unsupportedContext = enrichment(
            title: "Call pharmacy",
            friction: 2,
            interest: nil,
            confidence: 0.5
        )
        unsupportedContext.contextTag = "airport"
        #expect(throws: AIEnricherError.self) {
            try EnrichmentResultValidator.validate(
                unsupportedContext,
                provider: .openai,
                allowInterest: false
            )
        }

        #expect(
            EnrichmentPrompt.jsonSchema(allowInterest: false)
                .contains(#""additionalProperties": false"#)
        )
    }

    @Test func DeepSeekRequiresExplicitNonAliasModel() {
        #expect(AIProvider.deepseek.isReleaseEnabled == false)
        #expect(AIEnricherRegistry.enricher(for: .deepseek) == nil)
        #expect(AIProvider.deepseek.defaultModel.isEmpty)
        #expect(DeepSeekEnricher.configuredModel(from: nil) == nil)
        #expect(DeepSeekEnricher.configuredModel(from: "deepseek-chat") == nil)
        #expect(DeepSeekEnricher.configuredModel(from: "deepseek-reasoner") == nil)
        #expect(
            DeepSeekEnricher.configuredModel(from: "  provider-model-id  ")
                == "provider-model-id"
        )
    }

    @Test func cloudProviderConsentIsVersionedAndDisclosesEveryPersonalField() {
        #expect(AIConsentPolicy.currentDisclosureVersion == 3)

        for provider in AIProvider.allCases {
            guard case .cloud = provider.privacyTier else { continue }
            let disclosure = provider.consentDisclosure
            #expect(disclosure.contains("task title"))
            #expect(disclosure.contains("free-form note"))
            #expect(disclosure.contains("neurotype"))
            #expect(disclosure.contains("capacity mode"))
            #expect(disclosure.contains("response-tone"))
            #expect(disclosure.contains("interest inference"))
            #expect(disclosure.contains("About-you"))
            #expect(disclosure.contains("recent enriched task titles"))
            #expect(disclosure.contains("difficulty bands"))
            #expect(disclosure.contains("Retention and training"))
            #expect(provider.dataTermsURL?.scheme == "https")
        }
    }

    @Test func expiredOAuthTokenIsRecognized() {
        let tokens = OAuthTokens(
            accessToken: "expired",
            refreshToken: nil,
            expiresAt: Date.distantPast
        )
        #expect(tokens.isExpiredOrAboutTo)
    }

    @Test func OAuthFormEncodingEscapesTokenDelimiters() {
        let data = OAuthCoordinator.formURLEncoded([
            "refresh_token": "a+b&c=d",
            "redirect_uri": "com.example:/oauth2 redirect"
        ])
        let body = String(decoding: data, as: UTF8.self)
        #expect(body.contains("refresh_token=a%2Bb%26c%3Dd"))
        #expect(body.contains("redirect_uri=com.example%3A%2Foauth2%20redirect"))
    }

    @Test func googleOAuthRequiresMatchingRegisteredBundleConfiguration() {
        let clientID = "1234567890-example.apps.googleusercontent.com"
        let scheme = "com.googleusercontent.apps.1234567890-example"

        #expect(
            GoogleOAuth.validateConfiguration(
                clientID: clientID,
                redirectScheme: scheme,
                registeredSchemes: [scheme]
            )
        )
        #expect(
            GoogleOAuth.validateConfiguration(
                clientID: clientID,
                redirectScheme: scheme,
                registeredSchemes: []
            ) == false
        )
        #expect(
            GoogleOAuth.validateConfiguration(
                clientID: clientID,
                redirectScheme: "com.example.wrong",
                registeredSchemes: ["com.example.wrong"]
            ) == false
        )
        #expect(
            GoogleOAuth.validateConfiguration(
                clientID: "$(AUGENDA_GOOGLE_CLIENT_ID)",
                redirectScheme: scheme,
                registeredSchemes: [scheme]
            ) == false
        )
    }

    @Test func appleFoundationProviderCharacteristicsAndZeroCost() throws {
        let provider = AIProvider.appleFoundation
        #expect(provider.privacyTier == .onDevice)
        #expect(provider.requiresAPIKey == false)
        #expect(provider.defaultModel == "apple-foundation-3b")

        // Zero cost ledger entry
        #expect(AIUsageLedger.estimateCost(
            provider: provider.rawValue,
            promptTokens: 1_000_000,
            completionTokens: 0
        ) == 0)
        #expect(AIUsageLedger.estimateCost(
            provider: provider.rawValue,
            promptTokens: 0,
            completionTokens: 1_000_000
        ) == 0)

        // Local-only outbound policy compatibility
        let suiteName = "com.augenda.tests.ai-apple-foundation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "ai.enabled")
        defaults.set(true, forKey: "ai.localOnlyMode")

        #expect(AIConsentPolicy.hasCurrentConsent(for: .appleFoundation, defaults: defaults))
        #expect(throws: Never.self) {
            try AIOutboundPolicy.enforce(provider: .appleFoundation, defaults: defaults)
        }
    }

    @Test func appleFoundationBackupDefaultsAreResettable() {
        #expect(AppDefaultsKeys.resettable.contains("ai.backupProvider"))
        #expect(AppDefaultsKeys.resettable.contains("ai.enableBackupFallback"))
    }

    private func enrichment(
        title: String?,
        friction: Int?,
        interest: Int?,
        confidence: Double?
    ) -> TaskEnrichment {
        TaskEnrichment(
            title: title,
            taskDescription: nil,
            subTasks: nil,
            friction: friction,
            energy: nil,
            sensoryLoad: nil,
            socialLoad: nil,
            initiationCost: nil,
            interest: interest,
            estimatedMinutes: nil,
            contextTag: nil,
            bestTimeOfDay: nil,
            confidence: confidence,
            usage: nil
        )
    }
}
