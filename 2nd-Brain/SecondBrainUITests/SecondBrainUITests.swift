import XCTest

private enum LaunchEnvironmentKeys {
    static let mode = "SECOND_BRAIN_UI_TEST_MODE"
    static let dataset = "SECOND_BRAIN_UI_TEST_DATASET"
    static let assistant = "SECOND_BRAIN_UI_TEST_ASSISTANT"
    static let voice = "SECOND_BRAIN_UI_TEST_VOICE"
    static let microphonePermission = "SECOND_BRAIN_UI_TEST_MIC_PERMISSION"
}

struct SecondBrainUITestLaunchConfiguration {
    enum Dataset: String {
        case empty
        case standard
    }

    enum Assistant: String {
        case deterministicSearch
        case fixedReply
        case pendingEdit
    }

    enum Voice: String {
        case newNote
        case assistantPendingEdit
        case draftFallback
    }

    enum MicrophonePermission: String {
        case granted
        case denied
    }

    let dataset: Dataset
    let assistant: Assistant
    let voice: Voice
    let microphonePermission: MicrophonePermission

    static let empty = SecondBrainUITestLaunchConfiguration(
        dataset: .empty,
        assistant: .deterministicSearch,
        voice: .newNote,
        microphonePermission: .granted
    )

    static let seeded = SecondBrainUITestLaunchConfiguration(
        dataset: .standard,
        assistant: .deterministicSearch,
        voice: .newNote,
        microphonePermission: .granted
    )

    static let askNotesReply = SecondBrainUITestLaunchConfiguration(
        dataset: .standard,
        assistant: .fixedReply,
        voice: .newNote,
        microphonePermission: .granted
    )

    static let quickCapturePendingEdit = SecondBrainUITestLaunchConfiguration(
        dataset: .standard,
        assistant: .pendingEdit,
        voice: .assistantPendingEdit,
        microphonePermission: .granted
    )

    static let quickCaptureDraftFallback = SecondBrainUITestLaunchConfiguration(
        dataset: .standard,
        assistant: .fixedReply,
        voice: .draftFallback,
        microphonePermission: .granted
    )

    func makeApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-SECOND_BRAIN_UI_TEST_MODE",
            "-AppleLocale", "en_US_POSIX",
            "-AppleLanguages", "(en)"
        ]
        app.launchEnvironment[LaunchEnvironmentKeys.mode] = "1"
        app.launchEnvironment[LaunchEnvironmentKeys.dataset] = dataset.rawValue
        app.launchEnvironment[LaunchEnvironmentKeys.assistant] = assistant.rawValue
        app.launchEnvironment[LaunchEnvironmentKeys.voice] = voice.rawValue
        app.launchEnvironment[LaunchEnvironmentKeys.microphonePermission] = microphonePermission.rawValue
        app.launchEnvironment["TZ"] = "UTC"
        return app
    }
}

final class SecondBrainUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsMainActions() throws {
        let app = SecondBrainUITestLaunchConfiguration.seeded.makeApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Second Brain"].waitForExistence(timeout: 5) || app.staticTexts["Second Brain"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickCaptureButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["askNotesButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchShowsEmptyStateInDeterministicMode() throws {
        let app = SecondBrainUITestLaunchConfiguration.empty.makeApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickCaptureButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["askNotesButton"].waitForExistence(timeout: 5))
    }
}

// MARK: - SecondBrainUITestLaunchConfiguration unit tests (no app launch)

final class SecondBrainUITestLaunchConfigurationTests: XCTestCase {

    // MARK: Static preset values

    func testEmptyPresetValues() {
        let config = SecondBrainUITestLaunchConfiguration.empty

        XCTAssertEqual(config.dataset, .empty)
        XCTAssertEqual(config.assistant, .deterministicSearch)
        XCTAssertEqual(config.voice, .newNote)
        XCTAssertEqual(config.microphonePermission, .granted)
    }

    func testSeededPresetValues() {
        let config = SecondBrainUITestLaunchConfiguration.seeded

        XCTAssertEqual(config.dataset, .standard)
        XCTAssertEqual(config.assistant, .deterministicSearch)
        XCTAssertEqual(config.voice, .newNote)
        XCTAssertEqual(config.microphonePermission, .granted)
    }

    func testAskNotesReplyPresetValues() {
        let config = SecondBrainUITestLaunchConfiguration.askNotesReply

        XCTAssertEqual(config.dataset, .standard)
        XCTAssertEqual(config.assistant, .fixedReply)
        XCTAssertEqual(config.voice, .newNote)
        XCTAssertEqual(config.microphonePermission, .granted)
    }

    func testQuickCapturePendingEditPresetValues() {
        let config = SecondBrainUITestLaunchConfiguration.quickCapturePendingEdit

        XCTAssertEqual(config.dataset, .standard)
        XCTAssertEqual(config.assistant, .pendingEdit)
        XCTAssertEqual(config.voice, .assistantPendingEdit)
        XCTAssertEqual(config.microphonePermission, .granted)
    }

    func testQuickCaptureDraftFallbackPresetValues() {
        let config = SecondBrainUITestLaunchConfiguration.quickCaptureDraftFallback

        XCTAssertEqual(config.dataset, .standard)
        XCTAssertEqual(config.assistant, .fixedReply)
        XCTAssertEqual(config.voice, .draftFallback)
        XCTAssertEqual(config.microphonePermission, .granted)
    }

    // MARK: makeApplication() environment variables

    func testMakeApplicationSetsUITestModeEnvironmentVariable() {
        let app = SecondBrainUITestLaunchConfiguration.seeded.makeApplication()

        XCTAssertEqual(app.launchEnvironment[LaunchEnvironmentKeys.mode], "1")
    }

    func testMakeApplicationSetsDatasetEnvironmentVariable() {
        let app = SecondBrainUITestLaunchConfiguration.empty.makeApplication()

        XCTAssertEqual(app.launchEnvironment[LaunchEnvironmentKeys.dataset], SecondBrainUITestLaunchConfiguration.Dataset.empty.rawValue)
    }

    func testMakeApplicationSetsAssistantEnvironmentVariable() {
        let app = SecondBrainUITestLaunchConfiguration.askNotesReply.makeApplication()

        XCTAssertEqual(app.launchEnvironment[LaunchEnvironmentKeys.assistant], SecondBrainUITestLaunchConfiguration.Assistant.fixedReply.rawValue)
    }

    func testMakeApplicationSetsVoiceEnvironmentVariable() {
        let app = SecondBrainUITestLaunchConfiguration.quickCapturePendingEdit.makeApplication()

        XCTAssertEqual(app.launchEnvironment[LaunchEnvironmentKeys.voice], SecondBrainUITestLaunchConfiguration.Voice.assistantPendingEdit.rawValue)
    }

    func testMakeApplicationSetsMicrophonePermissionEnvironmentVariable() {
        let app = SecondBrainUITestLaunchConfiguration.seeded.makeApplication()

        XCTAssertEqual(app.launchEnvironment[LaunchEnvironmentKeys.microphonePermission], SecondBrainUITestLaunchConfiguration.MicrophonePermission.granted.rawValue)
    }

    func testMakeApplicationSetsUTCTimezoneEnvironmentVariable() {
        let app = SecondBrainUITestLaunchConfiguration.seeded.makeApplication()

        XCTAssertEqual(app.launchEnvironment["TZ"], "UTC")
    }

    // MARK: makeApplication() launch arguments

    func testMakeApplicationIncludesUITestModeArgument() {
        let app = SecondBrainUITestLaunchConfiguration.seeded.makeApplication()

        XCTAssertTrue(app.launchArguments.contains("-SECOND_BRAIN_UI_TEST_MODE"))
    }

    func testMakeApplicationIncludesEnglishLocaleArguments() {
        let app = SecondBrainUITestLaunchConfiguration.seeded.makeApplication()

        XCTAssertTrue(app.launchArguments.contains("-AppleLocale"))
        XCTAssertTrue(app.launchArguments.contains("en_US_POSIX"))
        XCTAssertTrue(app.launchArguments.contains("-AppleLanguages"))
        XCTAssertTrue(app.launchArguments.contains("(en)"))
    }

    func testMakeApplicationCustomConfigurationReflectedInEnvironment() {
        let config = SecondBrainUITestLaunchConfiguration(
            dataset: .empty,
            assistant: .pendingEdit,
            voice: .draftFallback,
            microphonePermission: .denied
        )
        let app = config.makeApplication()

        XCTAssertEqual(app.launchEnvironment[LaunchEnvironmentKeys.dataset], SecondBrainUITestLaunchConfiguration.Dataset.empty.rawValue)
        XCTAssertEqual(app.launchEnvironment[LaunchEnvironmentKeys.assistant], SecondBrainUITestLaunchConfiguration.Assistant.pendingEdit.rawValue)
        XCTAssertEqual(app.launchEnvironment[LaunchEnvironmentKeys.voice], SecondBrainUITestLaunchConfiguration.Voice.draftFallback.rawValue)
        XCTAssertEqual(app.launchEnvironment[LaunchEnvironmentKeys.microphonePermission], SecondBrainUITestLaunchConfiguration.MicrophonePermission.denied.rawValue)
    }
}
