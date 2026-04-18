import Foundation
import Testing
@testable import SecondBrainDomain

@MainActor
struct SecondBrainDomainVoiceCaptureTests {
    @Test
    @MainActor
    func processVoiceCaptureFallsBackToRawTranscriptWhenIntelligenceIsUnavailable() async throws {
        let repository = InMemoryNoteRepository()
        let sourceURL = try makeSourceAudioFile()
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }

        let useCase = ProcessVoiceCaptureUseCase(
            repository: repository,
            transcriptionService: MockSpeechTranscriptionService(result: "raw transcript from speech"),
            captureIntelligence: MockNoteCaptureIntelligenceService(
                capabilityState: .unavailable(reason: "AI-assisted capture is unavailable on watchOS."),
                typedResult: NoteCaptureRefinement(title: "", body: ""),
                transcriptResult: NoteCaptureRefinement(title: "Ignored", body: "Ignored")
            ),
            interpretationService: MockVoiceCaptureInterpretationService(
                result: VoiceCaptureInterpretation(
                    intent: .newNote,
                    normalizedText: "raw transcript from speech"
                )
            ),
            assistant: MockNotesAssistantService(
                capabilityState: .available,
                response: NotesAssistantResponse(text: "", referencedNoteIDs: [])
            )
        )

        let result = try await useCase.execute(
            title: "",
            audioURL: sourceURL,
            locale: .current,
            source: .speechToText
        )

        switch result {
        case let .createdNote(note):
            #expect(note.displayTitle == "raw transcript from speech")
            #expect(note.body == "raw transcript from speech")
            #expect(note.entries.first?.kind == .transcription)
        case .assistantResponse:
            Issue.record("Expected a created note result.")
        }
    }

    @Test
    @MainActor
    func processVoiceCaptureRoutesAssistantCommandsAndPreservesTranscript() async throws {
        let repository = InMemoryNoteRepository()
        let sourceURL = try makeSourceAudioFile()
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        let noteID = UUID()

        let useCase = ProcessVoiceCaptureUseCase(
            repository: repository,
            transcriptionService: MockSpeechTranscriptionService(result: "replace banana with avocado"),
            captureIntelligence: MockNoteCaptureIntelligenceService(
                typedResult: NoteCaptureRefinement(title: "", body: ""),
                transcriptResult: NoteCaptureRefinement(title: "", body: "")
            ),
            interpretationService: MockVoiceCaptureInterpretationService(
                result: VoiceCaptureInterpretation(
                    intent: .assistantCommand,
                    normalizedText: "in the shopping list, replace banana with avocado"
                )
            ),
            assistant: MockNotesAssistantService(
                capabilityState: .available,
                response: NotesAssistantResponse(
                    text: "Updated note Shopping list.",
                    referencedNoteIDs: [noteID]
                )
            )
        )

        let result = try await useCase.execute(
            title: "",
            audioURL: sourceURL,
            locale: .current,
            source: .speechToText
        )

        switch result {
        case .createdNote:
            Issue.record("Expected an assistant response result.")
        case let .assistantResponse(response, transcript):
            #expect(response.text == "Updated note Shopping list.")
            #expect(response.referencedNoteIDs == [noteID])
            #expect(response.interaction == .none)
            #expect(transcript == "replace banana with avocado")
        }
    }

}
