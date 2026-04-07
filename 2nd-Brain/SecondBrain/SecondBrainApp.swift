import SwiftUI
import SecondBrainComposition

@main
struct SecondBrainApp: App {
    private let startupCoordinator: AppStartupCoordinator

    init() {
        if let configuration = UITestHarnessConfiguration.current() {
            startupCoordinator = AppStartupCoordinator {
                try AppGraph.uiTest(configuration.graphConfiguration)
            }
        } else {
            startupCoordinator = AppStartupCoordinator()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppStartupContainerView(coordinator: startupCoordinator) { graph in
                ContentView(graph: graph)
            }
        }
    }
}

private struct UITestHarnessConfiguration {
    let graphConfiguration: AppGraph.UITestConfiguration

    /// Builds the UI test harness configuration from process state when test mode is enabled.
    /// - Parameter processInfo: The `ProcessInfo` used to read environment variables and launch arguments. Defaults to `.processInfo`.
    /// - Returns: A `UITestHarnessConfiguration` built from environment variables when UI test harness mode is enabled; `nil` otherwise.
    /// - Note: Test mode is enabled by `SECOND_BRAIN_UI_TEST_MODE=1` or the `-SECOND_BRAIN_UI_TEST_MODE` launch argument.
    static func current(processInfo: ProcessInfo = .processInfo) -> UITestHarnessConfiguration? {
        let environment = processInfo.environment
        let arguments = processInfo.arguments
        let isEnabled = environment["SECOND_BRAIN_UI_TEST_MODE"] == "1"
            || arguments.contains("-SECOND_BRAIN_UI_TEST_MODE")
        guard isEnabled else {
            return nil
        }

        return UITestHarnessConfiguration(
            graphConfiguration: AppGraph.UITestConfiguration(
                dataset: AppGraph.UITestConfiguration.Dataset(
                    rawValue: environment["SECOND_BRAIN_UI_TEST_DATASET"] ?? ""
                ) ?? .standard,
                assistant: AppGraph.UITestConfiguration.Assistant(
                    rawValue: environment["SECOND_BRAIN_UI_TEST_ASSISTANT"] ?? ""
                ) ?? .deterministicSearch,
                voice: AppGraph.UITestConfiguration.Voice(
                    rawValue: environment["SECOND_BRAIN_UI_TEST_VOICE"] ?? ""
                ) ?? .newNote,
                microphonePermission: AppGraph.UITestConfiguration.MicrophonePermission(
                    rawValue: environment["SECOND_BRAIN_UI_TEST_MIC_PERMISSION"] ?? ""
                ) ?? .granted
            )
        )
    }
}
