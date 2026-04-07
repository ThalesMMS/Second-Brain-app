import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
import SecondBrainComposition
import SecondBrainDomain
@testable import SecondBrain

@MainActor
final class SecondBrainSnapshotTests: XCTestCase {
    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let timeZone = TimeZone(secondsFromGMT: 0)!
    private static let snapshotDate = Date(timeIntervalSinceReferenceDate: 781_063_200)
    private static let snapshotNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    private static let snapshotEntryID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    private static let reducedFunctionalityReason =
        "Apple Intelligence is unavailable on this device. Falling back to deterministic retrieval."
    private static let iPhone17Config = ViewImageConfig(
        safeArea: .init(top: 59, left: 0, bottom: 34, right: 0),
        size: .init(width: 402, height: 874),
        traits: UITraitCollection(mutations: {
            $0.userInterfaceIdiom = .phone
            $0.horizontalSizeClass = .compact
            $0.verticalSizeClass = .regular
            $0.displayScale = 3
            $0.preferredContentSizeCategory = .large
            $0.layoutDirection = .leftToRight
        })
    )

    private var snapshotCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Self.locale
        calendar.timeZone = Self.timeZone
        return calendar
    }

    override func invokeTest() {
        withSnapshotTesting(record: snapshotRecordMode()) {
            super.invokeTest()
        }
    }

    func testNotesListEmptyState() async throws {
        let graph = try AppGraph.uiTest(.init(dataset: .empty))
        let store = NotesStore(graph: graph)
        await store.refresh()

        assertSnapshot(
            of: NavigationStack {
                NotesListView(store: store, runsTasksOnAppear: false)
            }
        )
    }

    func testNotesListPopulatedState() async throws {
        let graph = try AppGraph.uiTest(.init(dataset: .standard))
        let store = NotesStore(graph: graph)
        await store.refresh()

        assertSnapshot(
            of: NavigationStack {
                NotesListView(store: store, runsTasksOnAppear: false)
            }
        )
    }

    func testQuickCaptureTextEntryState() {
        let viewModel = makeQuickCaptureViewModel()
        viewModel.title = "Residency prep"
        viewModel.body = "Call the program coordinator and gather the remaining documents."

        assertSnapshot(of: QuickCaptureView(viewModel: viewModel))
    }

    func testQuickCaptureVoiceFeedbackState() {
        let viewModel = makeQuickCaptureViewModel()
        viewModel.transcriptionPreview = "Summarize my oncology reminders."
        viewModel.voiceAssistantMessage = "I found the Oncology reminders note and summarized the next actions."

        assertSnapshot(of: QuickCaptureView(viewModel: viewModel))
    }

    func testQuickCapturePendingConfirmationState() {
        let viewModel = makeQuickCaptureViewModel()
        viewModel.transcriptionPreview = "Add butter to the shopping list."
        viewModel.voiceAssistantMessage = "I can update Shopping list to add Butter. Confirm or Cancel."
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation

        assertSnapshot(of: QuickCaptureView(viewModel: viewModel))
    }

    func testAskNotesEmptyConversationState() {
        assertSnapshot(
            of: AskNotesView(
                viewModel: AskNotesViewModel(capabilityState: .available)
            )
        )
    }

    func testAskNotesPopulatedConversationState() {
        let viewModel = AskNotesViewModel(
            messages: [
                AssistantMessage(role: .user, text: "Summarize my shopping list."),
                AssistantMessage(
                    role: .assistant,
                    text: "Shopping list currently contains Milk, Eggs, and Bread."
                ),
            ],
            capabilityState: .available
        )

        assertSnapshot(of: AskNotesView(viewModel: viewModel))
    }

    func testAskNotesReducedFunctionalityBannerState() {
        let viewModel = AskNotesViewModel(
            capabilityState: .available,
            assistantStatus: .reducedFunctionality(reason: Self.reducedFunctionalityReason)
        )

        assertSnapshot(of: AskNotesView(viewModel: viewModel))
    }

    func testNoteDetailLoadedState() async throws {
        let graph = try AppGraph.uiTest(.init(dataset: .standard))
        let viewModel = NoteDetailViewModel(
            noteID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            graph: graph
        )
        await viewModel.load()

        assertSnapshot(
            of: NavigationStack {
                NoteDetailView(viewModel: viewModel, onDeleted: {})
            }
        )
    }

    func testNoteDetailUnavailableState() async throws {
        let graph = try AppGraph.uiTest(.init(dataset: .standard))
        let viewModel = NoteDetailViewModel(noteID: UUID(), graph: graph)
        await viewModel.load()

        assertSnapshot(
            of: NavigationStack {
                NoteDetailView(viewModel: viewModel, onDeleted: {})
            }
        )
    }

    private func makeQuickCaptureViewModel() -> QuickCaptureViewModel {
        QuickCaptureViewModel(
            dependencies: .init(
                captureCapabilityState: { .available },
                voiceCommandCapabilityState: { .available },
                refineTypedNote: { title, body, _ in
                    NoteCaptureRefinement(title: title, body: body)
                },
                createNote: { title, body, source in
                    Note(
                        id: Self.snapshotNoteID,
                        title: title,
                        body: body,
                        createdAt: Self.snapshotDate,
                        updatedAt: Self.snapshotDate,
                        entries: [
                            NoteEntry(
                                id: Self.snapshotEntryID,
                                createdAt: Self.snapshotDate,
                                kind: .creation,
                                source: source,
                                text: body
                            )
                        ]
                    )
                },
                requestRecordingPermission: { true },
                makeTemporaryRecordingURL: { URL(fileURLWithPath: "/tmp/secondbrain-snapshot.m4a") },
                startRecording: { _ in },
                stopRecording: {
                    RecordedAudio(
                        temporaryFileURL: URL(fileURLWithPath: "/tmp/secondbrain-snapshot.m4a"),
                        durationSeconds: 1
                    )
                },
                cancelRecording: {},
                processVoiceCapture: { _, _, _, _ in
                    .assistantResponse(
                        NotesAssistantResponse(
                            text: "Snapshot placeholder response.",
                            referencedNoteIDs: []
                        ),
                        transcript: "Snapshot placeholder transcript."
                    )
                },
                processAssistantInput: { _ in
                    NotesAssistantResponse(text: "Snapshot placeholder response.", referencedNoteIDs: [])
                }
            ),
            onSaved: {}
        )
    }

    private func assertSnapshot<Content: View>(
        of view: Content,
        named name: String? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let controller = UIHostingController(
            rootView: view
                .environment(\.locale, Self.locale)
                .environment(\.calendar, snapshotCalendar)
                .environment(\.timeZone, Self.timeZone)
                .environment(\.dynamicTypeSize, .large)
                .preferredColorScheme(.light)
        )
        controller.overrideUserInterfaceStyle = .light
        controller.view.backgroundColor = .systemBackground

        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(wereAnimationsEnabled) }

        SnapshotTesting.assertSnapshot(
            of: controller,
            as: .image(on: Self.iPhone17Config),
            named: name,
            file: file,
            testName: testName,
            line: line
        )
    }

    private func snapshotRecordMode() -> SnapshotTestingConfiguration.Record {
        let environment = ProcessInfo.processInfo.environment
        let shouldRecord =
            environment["RECORD_SNAPSHOTS"] == "1"
            || environment["SIMCTL_CHILD_RECORD_SNAPSHOTS"] == "1"
            || FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .appendingPathComponent(".record_snapshots")
                    .path
            )
        return shouldRecord ? .all : .never
    }
}
