import AppIntents
import Foundation
import Testing
import SecondBrainComposition
import SecondBrainDomain
@testable import SecondBrain

actor GraphInjectionCoordinator {
    static let shared = GraphInjectionCoordinator()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func runExclusive<T>(
        _ block: @MainActor () async throws -> T
    ) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await block()
    }

    private func acquire() async {
        guard isRunning else {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            isRunning = false
        }
    }
}

func makeTemporaryRecordingURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
}

@MainActor
func makeInMemoryGraph() throws -> AppGraph {
    try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
}

enum SeedNotesError: Error, Equatable, Sendable {
    case invalidCount(count: Int)
}

@MainActor
func makeMinimalDependencies(
    requestRecordingPermission: @escaping @MainActor () async -> Bool = { false },
    stopRecording: @escaping @MainActor () throws -> RecordedAudio = {
        RecordedAudio(
            temporaryFileURL: makeTemporaryRecordingURL(),
            durationSeconds: 0
        )
    },
    processVoiceCapture: @escaping @MainActor (_ title: String, _ audioURL: URL, _ locale: Locale, _ source: NoteMutationSource) async throws -> VoiceCaptureResult = { _, _, _, _ in
        .assistantResponse(
            NotesAssistantResponse(text: "", referencedNoteIDs: []),
            transcript: ""
        )
    },
    processAssistantInput: @escaping @MainActor (_ input: String) async throws -> NotesAssistantResponse = { _ in
        NotesAssistantResponse(text: "", referencedNoteIDs: [])
    }
) -> QuickCaptureViewModel.Dependencies {
    QuickCaptureViewModel.Dependencies(
        captureCapabilityState: { .available },
        voiceCommandCapabilityState: { .available },
        refineTypedNote: { title, body, _ in NoteCaptureRefinement(title: title, body: body) },
        createNote: { _, _, _ in
            throw NoteRepositoryError.emptyContent
        },
        requestRecordingPermission: requestRecordingPermission,
        makeTemporaryRecordingURL: makeTemporaryRecordingURL,
        startRecording: { _ in },
        stopRecording: stopRecording,
        cancelRecording: {},
        processVoiceCapture: processVoiceCapture,
        processAssistantInput: processAssistantInput
    )
}

@MainActor
func withInjectedGraph<T>(
    _ graphFactory: @escaping @MainActor () throws -> AppGraph,
    operation: @MainActor () async throws -> T
) async rethrows -> T {
    try await GraphInjectionCoordinator.shared.runExclusive {
        let originalGraphFactory = NoteIntentEnvironment.graph
        NoteIntentEnvironment.graph = graphFactory
        defer { NoteIntentEnvironment.graph = originalGraphFactory }
        return try await operation()
    }
}

func dialogDescription<T>(of result: T) -> String {
    String(describing: Mirror(reflecting: result).descendant("dialog"))
        .replacingOccurrences(of: "\\'", with: "'")
}

func makeUITestAudioURL() -> URL {
    makeTemporaryRecordingURL()
}

extension AppGraph {
    @MainActor
    func executeUITestVoiceCapture() async throws -> VoiceCaptureResult {
        try await processVoiceCapture.execute(
            title: "",
            audioURL: makeUITestAudioURL(),
            locale: Locale(identifier: "en_US_POSIX"),
            source: .speechToText
        )
    }
}

@MainActor
func seedNotes(
    in graph: AppGraph,
    count: Int,
    titlePrefix: String,
    bodyPrefix: String
) async throws {
    guard count >= 0 else {
        throw SeedNotesError.invalidCount(count: count)
    }

    for index in 0..<count {
        _ = try await graph.createNote.execute(
            title: "\(titlePrefix) \(index)",
            body: "\(bodyPrefix) \(index)",
            source: .manual
        )
    }
}
