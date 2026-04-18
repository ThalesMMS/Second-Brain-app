import Testing
import SecondBrainComposition
import SecondBrainDomain

@Suite
struct UITestConfigurationTests {
    @Test
    func uiTestConfigurationDefaultsToStandardDatasetAndDeterministicSearch() {
        let config = AppGraph.UITestConfiguration()

        #expect(config.dataset == .standard)
        #expect(config.assistant == .deterministicSearch)
        #expect(config.voice == .newNote)
        #expect(config.microphonePermission == .granted)
    }

    @Test
    func uiTestConfigurationCanBeCustomized() {
        let config = AppGraph.UITestConfiguration(
            dataset: .empty,
            assistant: .pendingEdit,
            voice: .draftFallback,
            microphonePermission: .denied
        )

        #expect(config.dataset == .empty)
        #expect(config.assistant == .pendingEdit)
        #expect(config.voice == .draftFallback)
        #expect(config.microphonePermission == .denied)
    }

    @Test
    func uiTestConfigurationDatasetRawValuesRoundTrip() {
        #expect(AppGraph.UITestConfiguration.Dataset(rawValue: "empty") == .empty)
        #expect(AppGraph.UITestConfiguration.Dataset(rawValue: "standard") == .standard)
        #expect(AppGraph.UITestConfiguration.Dataset(rawValue: "unknown") == nil)
        #expect(AppGraph.UITestConfiguration.Dataset.empty.rawValue == "empty")
        #expect(AppGraph.UITestConfiguration.Dataset.standard.rawValue == "standard")
    }

    @Test
    func uiTestConfigurationAssistantRawValuesRoundTrip() {
        #expect(AppGraph.UITestConfiguration.Assistant(rawValue: "deterministicSearch") == .deterministicSearch)
        #expect(AppGraph.UITestConfiguration.Assistant(rawValue: "fixedReply") == .fixedReply)
        #expect(AppGraph.UITestConfiguration.Assistant(rawValue: "pendingEdit") == .pendingEdit)
        #expect(AppGraph.UITestConfiguration.Assistant(rawValue: "invalid") == nil)
        #expect(AppGraph.UITestConfiguration.Assistant.deterministicSearch.rawValue == "deterministicSearch")
        #expect(AppGraph.UITestConfiguration.Assistant.fixedReply.rawValue == "fixedReply")
        #expect(AppGraph.UITestConfiguration.Assistant.pendingEdit.rawValue == "pendingEdit")
    }

    @Test
    func uiTestConfigurationVoiceRawValuesRoundTrip() {
        #expect(AppGraph.UITestConfiguration.Voice(rawValue: "newNote") == .newNote)
        #expect(AppGraph.UITestConfiguration.Voice(rawValue: "assistantPendingEdit") == .assistantPendingEdit)
        #expect(AppGraph.UITestConfiguration.Voice(rawValue: "draftFallback") == .draftFallback)
        #expect(AppGraph.UITestConfiguration.Voice(rawValue: "bogus") == nil)
        #expect(AppGraph.UITestConfiguration.Voice.newNote.rawValue == "newNote")
        #expect(AppGraph.UITestConfiguration.Voice.assistantPendingEdit.rawValue == "assistantPendingEdit")
        #expect(AppGraph.UITestConfiguration.Voice.draftFallback.rawValue == "draftFallback")
    }

    @Test
    func uiTestConfigurationMicrophonePermissionRawValuesRoundTrip() {
        #expect(AppGraph.UITestConfiguration.MicrophonePermission(rawValue: "granted") == .granted)
        #expect(AppGraph.UITestConfiguration.MicrophonePermission(rawValue: "denied") == .denied)
        #expect(AppGraph.UITestConfiguration.MicrophonePermission(rawValue: "unknown") == nil)
        #expect(AppGraph.UITestConfiguration.MicrophonePermission.granted.rawValue == "granted")
        #expect(AppGraph.UITestConfiguration.MicrophonePermission.denied.rawValue == "denied")
    }

    // MARK: - Additional edge cases

    @Test
    func uiTestConfigurationTwoConfigurationsWithIdenticalParametersAreEqual() {
        let a = AppGraph.UITestConfiguration(
            dataset: .standard,
            assistant: .fixedReply,
            voice: .draftFallback,
            microphonePermission: .denied
        )
        let b = AppGraph.UITestConfiguration(
            dataset: .standard,
            assistant: .fixedReply,
            voice: .draftFallback,
            microphonePermission: .denied
        )

        #expect(a.dataset == b.dataset)
        #expect(a.assistant == b.assistant)
        #expect(a.voice == b.voice)
        #expect(a.microphonePermission == b.microphonePermission)
    }

    @Test
    func uiTestConfigurationDefaultAndExplicitStandardDatasetAreEquivalent() {
        let defaultConfig = AppGraph.UITestConfiguration()
        let explicitConfig = AppGraph.UITestConfiguration(dataset: .standard)

        #expect(defaultConfig.dataset == explicitConfig.dataset)
    }

    @Test
    func uiTestConfigurationDatasetKnownRawValuesAreValid() {
        // Verify that all known Dataset cases have stable raw values — no regressions
        // if a case is renamed or removed.
        let allRawValues = ["empty", "standard"]
        for raw in allRawValues {
            #expect(AppGraph.UITestConfiguration.Dataset(rawValue: raw) != nil)
        }
    }

    @Test
    func uiTestConfigurationAssistantKnownRawValuesAreValid() {
        let allRawValues = ["deterministicSearch", "fixedReply", "pendingEdit"]
        for raw in allRawValues {
            #expect(AppGraph.UITestConfiguration.Assistant(rawValue: raw) != nil)
        }
    }

    @Test
    func uiTestConfigurationVoiceKnownRawValuesAreValid() {
        let allRawValues = ["newNote", "assistantPendingEdit", "draftFallback"]
        for raw in allRawValues {
            #expect(AppGraph.UITestConfiguration.Voice(rawValue: raw) != nil)
        }
    }

    @Test
    func uiTestConfigurationMicrophonePermissionKnownRawValuesAreValid() {
        let allRawValues = ["granted", "denied"]
        for raw in allRawValues {
            #expect(AppGraph.UITestConfiguration.MicrophonePermission(rawValue: raw) != nil)
        }
    }
}
