import Foundation
import Testing
@testable import SecondBrainAI
@testable import SecondBrainDomain

#if canImport(WatchConnectivity)

// MARK: - CompanionRelayMessageCodec: Encoding

struct CompanionRelayCodecEncodingTests {

    // MARK: assistantRequest

    @Test
    func assistantRequestEncodesKindAsAssistant() {
        let id = UUID()
        let dict = CompanionRelayMessageCodec.assistantRequest(id: id, prompt: "find my notes")

        #expect(dict["kind"] as? String == "assistant")
    }

    @Test
    func assistantRequestEncodesIdAsUUIDString() {
        let id = UUID()
        let dict = CompanionRelayMessageCodec.assistantRequest(id: id, prompt: "query")

        #expect(dict["id"] as? String == id.uuidString)
    }

    @Test
    func assistantRequestEncodesPrompt() {
        let id = UUID()
        let prompt = "find MRI notes"
        let dict = CompanionRelayMessageCodec.assistantRequest(id: id, prompt: prompt)

        #expect(dict["prompt"] as? String == prompt)
    }

    @Test
    func assistantRequestContainsExactlyThreeKeys() {
        let dict = CompanionRelayMessageCodec.assistantRequest(id: UUID(), prompt: "hello")
        #expect(dict.count == 3)
    }

    // MARK: voiceInterpretationRequest

    @Test
    func voiceInterpretationRequestEncodesKindAsVoiceInterpretation() {
        let dict = CompanionRelayMessageCodec.voiceInterpretationRequest(
            id: UUID(),
            transcript: "buy milk",
            locale: Locale(identifier: "en_US")
        )
        #expect(dict["kind"] as? String == "voiceInterpretation")
    }

    @Test
    func voiceInterpretationRequestEncodesLocaleIdentifier() {
        let dict = CompanionRelayMessageCodec.voiceInterpretationRequest(
            id: UUID(),
            transcript: "buy milk",
            locale: Locale(identifier: "pt_BR")
        )
        #expect(dict["localeIdentifier"] as? String == "pt_BR")
    }

    @Test
    func voiceInterpretationRequestEncodesTranscript() {
        let transcript = "schedule meeting tomorrow"
        let dict = CompanionRelayMessageCodec.voiceInterpretationRequest(
            id: UUID(),
            transcript: transcript,
            locale: .current
        )
        #expect(dict["transcript"] as? String == transcript)
    }

    @Test
    func voiceInterpretationRequestEncodesId() {
        let id = UUID()
        let dict = CompanionRelayMessageCodec.voiceInterpretationRequest(
            id: id,
            transcript: "hello",
            locale: .current
        )
        #expect(dict["id"] as? String == id.uuidString)
    }

    // MARK: assistantResponse

    @Test
    func assistantResponseEncodesTextAndId() {
        let id = UUID()
        let noteID = UUID()
        let response = NotesAssistantResponse(
            text: "Found your note.",
            referencedNoteIDs: [noteID],
            interaction: .none
        )
        let dict = CompanionRelayMessageCodec.assistantResponse(id: id, response: response)

        #expect(dict["id"] as? String == id.uuidString)
        #expect(dict["text"] as? String == "Found your note.")
    }

    @Test
    func assistantResponseEncodesReferencedNoteIDs() {
        let id = UUID()
        let note1 = UUID()
        let note2 = UUID()
        let response = NotesAssistantResponse(
            text: "Two notes.",
            referencedNoteIDs: [note1, note2],
            interaction: .none
        )
        let dict = CompanionRelayMessageCodec.assistantResponse(id: id, response: response)
        let encoded = dict["referencedNoteIDs"] as? [String] ?? []

        #expect(encoded.contains(note1.uuidString))
        #expect(encoded.contains(note2.uuidString))
        #expect(encoded.count == 2)
    }

    @Test
    func assistantResponseEncodesEmptyReferencedNoteIDs() {
        let dict = CompanionRelayMessageCodec.assistantResponse(
            id: UUID(),
            response: NotesAssistantResponse(text: "No notes.", referencedNoteIDs: [], interaction: .none)
        )
        let encoded = dict["referencedNoteIDs"] as? [String] ?? ["non-empty"]
        #expect(encoded.isEmpty)
    }

    @Test
    func assistantResponseEncodesPendingEditInteraction() {
        let dict = CompanionRelayMessageCodec.assistantResponse(
            id: UUID(),
            response: NotesAssistantResponse(
                text: "Proposed edit.",
                referencedNoteIDs: [],
                interaction: .pendingEditConfirmation
            )
        )
        #expect(dict["interaction"] as? String == "pendingEditConfirmation")
    }

    @Test
    func assistantResponseEncodesNoneInteraction() {
        let dict = CompanionRelayMessageCodec.assistantResponse(
            id: UUID(),
            response: NotesAssistantResponse(text: "Done.", referencedNoteIDs: [], interaction: .none)
        )
        #expect(dict["interaction"] as? String == "none")
    }

    // MARK: voiceInterpretationResponse

    @Test
    func voiceInterpretationResponseEncodesNewNoteIntent() {
        let id = UUID()
        let interpretation = VoiceCaptureInterpretation(intent: .newNote, normalizedText: "Buy apples.")
        let dict = CompanionRelayMessageCodec.voiceInterpretationResponse(id: id, interpretation: interpretation)

        #expect(dict["id"] as? String == id.uuidString)
        #expect(dict["intent"] as? String == "newNote")
        #expect(dict["normalizedText"] as? String == "Buy apples.")
    }

    @Test
    func voiceInterpretationResponseEncodesAssistantCommandIntent() {
        let interpretation = VoiceCaptureInterpretation(intent: .assistantCommand, normalizedText: "Show shopping list")
        let dict = CompanionRelayMessageCodec.voiceInterpretationResponse(id: UUID(), interpretation: interpretation)

        #expect(dict["intent"] as? String == "assistantCommand")
        #expect(dict["normalizedText"] as? String == "Show shopping list")
    }

    // MARK: error

    @Test
    func errorPayloadIncludesMessageUnderErrorKey() {
        let dict = CompanionRelayMessageCodec.error(id: nil, message: "Something went wrong.")
        #expect(dict["error"] as? String == "Something went wrong.")
    }

    @Test
    func errorPayloadWithIdIncludesIdAsUUIDString() {
        let id = UUID()
        let dict = CompanionRelayMessageCodec.error(id: id, message: "Failed.")
        #expect(dict["id"] as? String == id.uuidString)
        #expect(dict["error"] as? String == "Failed.")
    }

    @Test
    func errorPayloadWithNilIdOmitsIdKey() {
        let dict = CompanionRelayMessageCodec.error(id: nil, message: "Failed.")
        #expect(dict["id"] == nil)
    }
}

// MARK: - CompanionRelayMessageCodec: Decoding Requests

struct CompanionRelayCodecDecodeRequestTests {

    // MARK: decodeAssistantRequest – happy path

    @Test
    func decodeAssistantRequestSucceedsWithValidPayload() throws {
        let id = UUID()
        let dict: [String: Any] = [
            "kind": "assistant",
            "id": id.uuidString,
            "prompt": "search notes"
        ]
        let request = try #require(CompanionRelayMessageCodec.decodeAssistantRequest(dict))

        #expect(request.id == id)
        #expect(request.prompt == "search notes")
    }

    // MARK: decodeAssistantRequest – failure paths

    @Test
    func decodeAssistantRequestReturnsNilForWrongKind() {
        let dict: [String: Any] = [
            "kind": "voiceInterpretation",
            "id": UUID().uuidString,
            "prompt": "hello"
        ]
        #expect(CompanionRelayMessageCodec.decodeAssistantRequest(dict) == nil)
    }

    @Test
    func decodeAssistantRequestReturnsNilWhenKindIsMissing() {
        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "prompt": "hello"
        ]
        #expect(CompanionRelayMessageCodec.decodeAssistantRequest(dict) == nil)
    }

    @Test
    func decodeAssistantRequestReturnsNilForInvalidUUID() {
        let dict: [String: Any] = [
            "kind": "assistant",
            "id": "not-a-uuid",
            "prompt": "hello"
        ]
        #expect(CompanionRelayMessageCodec.decodeAssistantRequest(dict) == nil)
    }

    @Test
    func decodeAssistantRequestReturnsNilWhenIdIsMissing() {
        let dict: [String: Any] = [
            "kind": "assistant",
            "prompt": "hello"
        ]
        #expect(CompanionRelayMessageCodec.decodeAssistantRequest(dict) == nil)
    }

    @Test
    func decodeAssistantRequestReturnsNilWhenPromptIsMissing() {
        let dict: [String: Any] = [
            "kind": "assistant",
            "id": UUID().uuidString
        ]
        #expect(CompanionRelayMessageCodec.decodeAssistantRequest(dict) == nil)
    }

    @Test
    func decodeAssistantRequestReturnsNilForEmptyDictionary() {
        #expect(CompanionRelayMessageCodec.decodeAssistantRequest([:]) == nil)
    }

    // MARK: decodeVoiceInterpretationRequest – happy path

    @Test
    func decodeVoiceInterpretationRequestSucceedsWithValidPayload() throws {
        let id = UUID()
        let dict: [String: Any] = [
            "kind": "voiceInterpretation",
            "id": id.uuidString,
            "transcript": "schedule a meeting",
            "localeIdentifier": "en_US"
        ]
        let request = try #require(CompanionRelayMessageCodec.decodeVoiceInterpretationRequest(dict))

        #expect(request.id == id)
        #expect(request.transcript == "schedule a meeting")
        #expect(request.localeIdentifier == "en_US")
    }

    // MARK: decodeVoiceInterpretationRequest – failure paths

    @Test
    func decodeVoiceInterpretationRequestReturnsNilForWrongKind() {
        let dict: [String: Any] = [
            "kind": "assistant",
            "id": UUID().uuidString,
            "transcript": "hello",
            "localeIdentifier": "en_US"
        ]
        #expect(CompanionRelayMessageCodec.decodeVoiceInterpretationRequest(dict) == nil)
    }

    @Test
    func decodeVoiceInterpretationRequestReturnsNilWhenTranscriptIsMissing() {
        let dict: [String: Any] = [
            "kind": "voiceInterpretation",
            "id": UUID().uuidString,
            "localeIdentifier": "en_US"
        ]
        #expect(CompanionRelayMessageCodec.decodeVoiceInterpretationRequest(dict) == nil)
    }

    @Test
    func decodeVoiceInterpretationRequestReturnsNilWhenLocaleIdentifierIsMissing() {
        let dict: [String: Any] = [
            "kind": "voiceInterpretation",
            "id": UUID().uuidString,
            "transcript": "hello"
        ]
        #expect(CompanionRelayMessageCodec.decodeVoiceInterpretationRequest(dict) == nil)
    }

    @Test
    func decodeVoiceInterpretationRequestReturnsNilForInvalidUUID() {
        let dict: [String: Any] = [
            "kind": "voiceInterpretation",
            "id": "bad-uuid",
            "transcript": "hello",
            "localeIdentifier": "en_US"
        ]
        #expect(CompanionRelayMessageCodec.decodeVoiceInterpretationRequest(dict) == nil)
    }

    @Test
    func decodeVoiceInterpretationRequestReturnsNilForEmptyDictionary() {
        #expect(CompanionRelayMessageCodec.decodeVoiceInterpretationRequest([:]) == nil)
    }
}

// MARK: - CompanionRelayMessageCodec: Decoding Responses

struct CompanionRelayCodecDecodeResponseTests {

    // MARK: decodeAssistantResponse – happy path

    @Test
    func decodeAssistantResponseReturnsResponseWithText() throws {
        let dict: [String: Any] = [
            "text": "Here are your notes.",
            "referencedNoteIDs": [] as [String],
            "interaction": "none"
        ]
        let response = try CompanionRelayMessageCodec.decodeAssistantResponse(dict)
        #expect(response.text == "Here are your notes.")
    }

    @Test
    func decodeAssistantResponseParsesReferencedNoteIDs() throws {
        let id1 = UUID()
        let id2 = UUID()
        let dict: [String: Any] = [
            "text": "Two notes.",
            "referencedNoteIDs": [id1.uuidString, id2.uuidString],
            "interaction": "none"
        ]
        let response = try CompanionRelayMessageCodec.decodeAssistantResponse(dict)
        #expect(response.referencedNoteIDs.contains(id1))
        #expect(response.referencedNoteIDs.contains(id2))
        #expect(response.referencedNoteIDs.count == 2)
    }

    @Test
    func decodeAssistantResponseDropsInvalidUUIDStrings() throws {
        let validID = UUID()
        let dict: [String: Any] = [
            "text": "Note.",
            "referencedNoteIDs": [validID.uuidString, "invalid-uuid", "also-not-a-uuid"],
            "interaction": "none"
        ]
        let response = try CompanionRelayMessageCodec.decodeAssistantResponse(dict)
        #expect(response.referencedNoteIDs == [validID])
    }

    @Test
    func decodeAssistantResponseDefaultsInteractionToNone() throws {
        let dict: [String: Any] = [
            "text": "Hello."
        ]
        let response = try CompanionRelayMessageCodec.decodeAssistantResponse(dict)
        #expect(response.interaction == .none)
    }

    @Test
    func decodeAssistantResponseDefaultsInteractionForUnknownRawValue() throws {
        let dict: [String: Any] = [
            "text": "Hello.",
            "interaction": "unknownFutureState"
        ]
        let response = try CompanionRelayMessageCodec.decodeAssistantResponse(dict)
        #expect(response.interaction == .none)
    }

    @Test
    func decodeAssistantResponseParsesPendingEditConfirmationInteraction() throws {
        let dict: [String: Any] = [
            "text": "Proposed edit.",
            "interaction": "pendingEditConfirmation"
        ]
        let response = try CompanionRelayMessageCodec.decodeAssistantResponse(dict)
        #expect(response.interaction == .pendingEditConfirmation)
    }

    @Test
    func decodeAssistantResponseDefaultsEmptyReferencedNoteIDsWhenKeyAbsent() throws {
        let dict: [String: Any] = [
            "text": "Hello."
        ]
        let response = try CompanionRelayMessageCodec.decodeAssistantResponse(dict)
        #expect(response.referencedNoteIDs.isEmpty)
    }

    // MARK: decodeAssistantResponse – error paths

    @Test
    func decodeAssistantResponseThrowsWhenErrorKeyPresent() {
        let dict: [String: Any] = [
            "error": "Apple Intelligence is unavailable.",
            "id": UUID().uuidString
        ]
        #expect(throws: NotesAssistantError.self) {
            _ = try CompanionRelayMessageCodec.decodeAssistantResponse(dict)
        }
    }

    @Test
    func decodeAssistantResponseThrowsWhenTextKeyMissing() {
        let dict: [String: Any] = [
            "referencedNoteIDs": [] as [String]
        ]
        #expect(throws: NotesAssistantError.self) {
            _ = try CompanionRelayMessageCodec.decodeAssistantResponse(dict)
        }
    }

    @Test
    func decodeAssistantResponseThrowsForEmptyDictionary() {
        #expect(throws: NotesAssistantError.self) {
            _ = try CompanionRelayMessageCodec.decodeAssistantResponse([:])
        }
    }

    @Test
    func decodeAssistantResponseErrorMessageMatchesErrorKey() {
        let errorMessage = "Companion relay is unavailable."
        let dict: [String: Any] = ["error": errorMessage]
        do {
            _ = try CompanionRelayMessageCodec.decodeAssistantResponse(dict)
            Issue.record("Expected an error to be thrown.")
        } catch NotesAssistantError.unavailable(let reason) {
            #expect(reason == errorMessage)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: decodeVoiceInterpretationResponse – happy path

    @Test
    func decodeVoiceInterpretationResponseReturnsNewNoteInterpretation() throws {
        let dict: [String: Any] = [
            "intent": "newNote",
            "normalizedText": "Buy apples tomorrow"
        ]
        let interpretation = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(dict)
        #expect(interpretation.intent == .newNote)
        #expect(interpretation.normalizedText == "Buy apples tomorrow")
    }

    @Test
    func decodeVoiceInterpretationResponseReturnsAssistantCommandInterpretation() throws {
        let dict: [String: Any] = [
            "intent": "assistantCommand",
            "normalizedText": "Show my shopping list"
        ]
        let interpretation = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(dict)
        #expect(interpretation.intent == .assistantCommand)
        #expect(interpretation.normalizedText == "Show my shopping list")
    }

    // MARK: decodeVoiceInterpretationResponse – error paths

    @Test
    func decodeVoiceInterpretationResponseThrowsWhenErrorKeyPresent() {
        let dict: [String: Any] = [
            "error": "Voice interpretation is unavailable."
        ]
        #expect(throws: VoiceCaptureInterpretationError.self) {
            _ = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(dict)
        }
    }

    @Test
    func decodeVoiceInterpretationResponseErrorMessageMatchesErrorKey() {
        let errorMessage = "The paired iPhone is unreachable."
        let dict: [String: Any] = ["error": errorMessage]
        do {
            _ = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(dict)
            Issue.record("Expected an error to be thrown.")
        } catch VoiceCaptureInterpretationError.unavailable(let reason) {
            #expect(reason == errorMessage)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func decodeVoiceInterpretationResponseThrowsWhenIntentIsInvalid() {
        let dict: [String: Any] = [
            "intent": "unknownIntent",
            "normalizedText": "some text"
        ]
        #expect(throws: VoiceCaptureInterpretationError.self) {
            _ = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(dict)
        }
    }

    @Test
    func decodeVoiceInterpretationResponseThrowsWhenNormalizedTextIsMissing() {
        let dict: [String: Any] = [
            "intent": "newNote"
        ]
        #expect(throws: VoiceCaptureInterpretationError.self) {
            _ = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(dict)
        }
    }

    @Test
    func decodeVoiceInterpretationResponseThrowsWhenIntentIsMissing() {
        let dict: [String: Any] = [
            "normalizedText": "Buy milk"
        ]
        #expect(throws: VoiceCaptureInterpretationError.self) {
            _ = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(dict)
        }
    }

    @Test
    func decodeVoiceInterpretationResponseThrowsForEmptyDictionary() {
        #expect(throws: VoiceCaptureInterpretationError.self) {
            _ = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse([:])
        }
    }
}

// MARK: - CompanionRelayMessageCodec: Round-Trip Tests

struct CompanionRelayCodecRoundTripTests {

    @Test
    func assistantRequestRoundTripsWithArbitraryPrompt() throws {
        let id = UUID()
        let prompt = "list notes about cardiology"

        let encoded = CompanionRelayMessageCodec.assistantRequest(id: id, prompt: prompt)
        let decoded = try #require(CompanionRelayMessageCodec.decodeAssistantRequest(encoded))

        #expect(decoded.id == id)
        #expect(decoded.prompt == prompt)
    }

    @Test
    func voiceInterpretationRequestRoundTripsWithPtBRLocale() throws {
        let id = UUID()
        let transcript = "agendar reunião amanhã"
        let locale = Locale(identifier: "pt_BR")

        let encoded = CompanionRelayMessageCodec.voiceInterpretationRequest(id: id, transcript: transcript, locale: locale)
        let decoded = try #require(CompanionRelayMessageCodec.decodeVoiceInterpretationRequest(encoded))

        #expect(decoded.id == id)
        #expect(decoded.transcript == transcript)
        #expect(decoded.localeIdentifier == "pt_BR")
    }

    @Test
    func assistantResponseRoundTripsWithMultipleReferencedNotes() throws {
        let requestID = UUID()
        let note1 = UUID()
        let note2 = UUID()
        let response = NotesAssistantResponse(
            text: "Found two notes.",
            referencedNoteIDs: [note1, note2],
            interaction: .pendingEditConfirmation
        )

        let encoded = CompanionRelayMessageCodec.assistantResponse(id: requestID, response: response)
        let decoded = try CompanionRelayMessageCodec.decodeAssistantResponse(encoded)

        #expect(decoded.text == response.text)
        #expect(decoded.referencedNoteIDs == response.referencedNoteIDs)
        #expect(decoded.interaction == .pendingEditConfirmation)
    }

    @Test
    func voiceInterpretationResponseRoundTripsNewNoteInterpretation() throws {
        let id = UUID()
        let interpretation = VoiceCaptureInterpretation(intent: .newNote, normalizedText: "Comprar leite.")

        let encoded = CompanionRelayMessageCodec.voiceInterpretationResponse(id: id, interpretation: interpretation)
        let decoded = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(encoded)

        #expect(decoded.intent == .newNote)
        #expect(decoded.normalizedText == "Comprar leite.")
    }

    @Test
    func voiceInterpretationResponseRoundTripsAssistantCommandInterpretation() throws {
        let id = UUID()
        let interpretation = VoiceCaptureInterpretation(intent: .assistantCommand, normalizedText: "Search for MRI notes")

        let encoded = CompanionRelayMessageCodec.voiceInterpretationResponse(id: id, interpretation: interpretation)
        let decoded = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(encoded)

        #expect(decoded.intent == .assistantCommand)
        #expect(decoded.normalizedText == "Search for MRI notes")
    }
}

#endif
