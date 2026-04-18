import Foundation
import Testing
@testable import SecondBrainAI
@testable import SecondBrainDomain

#if os(iOS) && canImport(WatchConnectivity)

// MARK: - CompanionRelayNotesAssistantHostCoordinator

@MainActor
struct CompanionRelayCoordinatorTests {

    // MARK: process – success

    @Test
    func processReturnsSuccessWhenAssistantIsAvailable() async {
        let expectedResponse = NotesAssistantResponse(
            text: "Found relevant notes.",
            referencedNoteIDs: [UUID()],
            interaction: .none
        )
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                MockNotesAssistantService(
                    capabilityState: .available,
                    response: expectedResponse
                )
            },
            interpretationFactory: {
                MockVoiceCaptureInterpretationService()
            }
        )

        let result = await coordinator.process(prompt: "find notes about MRI", conversationID: UUID())

        switch result {
        case let .success(response):
            #expect(response.text == expectedResponse.text)
            #expect(response.referencedNoteIDs == expectedResponse.referencedNoteIDs)
        case .failure:
            Issue.record("Expected success but got failure.")
        }
    }

    // MARK: process – unavailable

    @Test
    func processReturnsFailureWithReasonWhenAssistantIsUnavailable() async {
        let unavailableReason = "Apple Intelligence is not enabled."
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                MockNotesAssistantService(
                    capabilityState: .unavailable(reason: unavailableReason),
                    response: NotesAssistantResponse(text: "", referencedNoteIDs: [])
                )
            },
            interpretationFactory: {
                MockVoiceCaptureInterpretationService()
            }
        )

        let result = await coordinator.process(prompt: "hello", conversationID: UUID())

        switch result {
        case .success:
            Issue.record("Expected failure for unavailable assistant.")
        case let .failure(error):
            guard let assistantError = error as? NotesAssistantError else {
                Issue.record("Wrong error type: \(type(of: error))")
                return
            }
            switch assistantError {
            case let .unavailable(reason):
                #expect(reason == unavailableReason)
            }
        }
    }

    // MARK: process – error propagation

    @Test
    func processReturnsFailureWhenAssistantProcessThrows() async {
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                ThrowingNotesAssistantService()
            },
            interpretationFactory: {
                MockVoiceCaptureInterpretationService()
            }
        )

        let result = await coordinator.process(prompt: "query", conversationID: UUID())

        switch result {
        case .success:
            Issue.record("Expected failure from throwing assistant.")
        case let .failure(error):
            #expect(error is NotesAssistantError)
        }
    }

    // MARK: process – conversation caching

    @Test
    func processReusesCachedAssistantForSameConversationID() async {
        var callCount = 0
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                callCount += 1
                return MockNotesAssistantService(
                    capabilityState: .available,
                    response: NotesAssistantResponse(text: "Hello", referencedNoteIDs: [])
                )
            },
            interpretationFactory: {
                MockVoiceCaptureInterpretationService()
            }
        )
        let id = UUID()

        _ = await coordinator.process(prompt: "first", conversationID: id)
        _ = await coordinator.process(prompt: "second", conversationID: id)

        // Only one assistant should have been created
        #expect(callCount == 1)
    }

    @Test
    func processCreatesDistinctAssistantsForDifferentConversationIDs() async {
        var callCount = 0
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                callCount += 1
                return MockNotesAssistantService(
                    capabilityState: .available,
                    response: NotesAssistantResponse(text: "Hello", referencedNoteIDs: [])
                )
            },
            interpretationFactory: {
                MockVoiceCaptureInterpretationService()
            }
        )

        _ = await coordinator.process(prompt: "A", conversationID: UUID())
        _ = await coordinator.process(prompt: "B", conversationID: UUID())

        #expect(callCount == 2)
    }

    // MARK: process – cache pruning (max 8)

    @Test
    func processEvictsOldestConversationWhenCacheExceedsMaximum() async {
        var createdIDs: [UUID] = []
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                let assistantID = UUID()
                createdIDs.append(assistantID)
                return MockNotesAssistantService(
                    capabilityState: .available,
                    response: NotesAssistantResponse(text: "ok", referencedNoteIDs: [])
                )
            },
            interpretationFactory: {
                MockVoiceCaptureInterpretationService()
            }
        )

        // Fill 8 conversations to reach the maximum
        var conversationIDs: [UUID] = []
        for _ in 0..<8 {
            let id = UUID()
            conversationIDs.append(id)
            _ = await coordinator.process(prompt: "fill", conversationID: id)
        }

        // Adding a 9th should evict the oldest (first)
        let ninthID = UUID()
        _ = await coordinator.process(prompt: "ninth", conversationID: ninthID)

        // Accessing the first (evicted) conversation should create a new assistant
        let firstConversationID = conversationIDs[0]
        _ = await coordinator.process(prompt: "re-access first", conversationID: firstConversationID)

        // 9 initial + 1 re-creation after eviction = 10 factory calls
        #expect(createdIDs.count == 10)
    }

    @Test
    func processDoesNotEvictBeforeMaximumIsReached() async {
        var callCount = 0
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                callCount += 1
                return MockNotesAssistantService(
                    capabilityState: .available,
                    response: NotesAssistantResponse(text: "ok", referencedNoteIDs: [])
                )
            },
            interpretationFactory: {
                MockVoiceCaptureInterpretationService()
            }
        )

        // Create exactly 8 conversations (the maximum)
        var conversationIDs: [UUID] = []
        for _ in 0..<8 {
            let id = UUID()
            conversationIDs.append(id)
            _ = await coordinator.process(prompt: "fill", conversationID: id)
        }

        let countAfterFilling = callCount

        // Re-access the first conversation; it should still be cached
        _ = await coordinator.process(prompt: "re-access", conversationID: conversationIDs[0])

        // No new assistant should have been created
        #expect(callCount == countAfterFilling)
    }

    // MARK: interpret – success

    @Test
    func interpretReturnsSuccessWhenServiceIsAvailable() async {
        let expectedInterpretation = VoiceCaptureInterpretation(
            intent: .newNote,
            normalizedText: "Buy milk and eggs."
        )
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                MockNotesAssistantService(
                    capabilityState: .available,
                    response: NotesAssistantResponse(text: "", referencedNoteIDs: [])
                )
            },
            interpretationFactory: {
                MockVoiceCaptureInterpretationService(
                    capabilityState: .available,
                    result: expectedInterpretation
                )
            }
        )

        let result = await coordinator.interpret(transcript: "buy milk and eggs", locale: Locale(identifier: "en_US"))

        switch result {
        case let .success(interpretation):
            #expect(interpretation.intent == .newNote)
            #expect(interpretation.normalizedText == "Buy milk and eggs.")
        case .failure:
            Issue.record("Expected successful interpretation.")
        }
    }

    // MARK: interpret – unavailable

    @Test
    func interpretReturnsFailureWhenServiceIsUnavailable() async {
        let unavailableReason = "Voice routing requires iOS 26."
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                MockNotesAssistantService(
                    capabilityState: .available,
                    response: NotesAssistantResponse(text: "", referencedNoteIDs: [])
                )
            },
            interpretationFactory: {
                MockVoiceCaptureInterpretationService(
                    capabilityState: .unavailable(reason: unavailableReason),
                    result: VoiceCaptureInterpretation(intent: .newNote, normalizedText: "")
                )
            }
        )

        let result = await coordinator.interpret(transcript: "hello", locale: .current)

        switch result {
        case .success:
            Issue.record("Expected failure for unavailable interpretation service.")
        case let .failure(error):
            guard let interpretationError = error as? VoiceCaptureInterpretationError else {
                Issue.record("Wrong error type: \(type(of: error))")
                return
            }
            switch interpretationError {
            case let .unavailable(reason):
                #expect(reason == unavailableReason)
            }
        }
    }

    // MARK: interpret – lazy service creation

    @Test
    func interpretLazilyCreatesInterpretationService() async {
        var interpretationServiceCallCount = 0
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                MockNotesAssistantService(
                    capabilityState: .available,
                    response: NotesAssistantResponse(text: "", referencedNoteIDs: [])
                )
            },
            interpretationFactory: {
                interpretationServiceCallCount += 1
                return MockVoiceCaptureInterpretationService(
                    capabilityState: .available,
                    result: VoiceCaptureInterpretation(intent: .newNote, normalizedText: "test")
                )
            }
        )

        // Service should not be created yet
        #expect(interpretationServiceCallCount == 0)

        _ = await coordinator.interpret(transcript: "buy coffee", locale: .current)

        // Service should be created on first call
        #expect(interpretationServiceCallCount == 1)

        _ = await coordinator.interpret(transcript: "buy tea", locale: .current)

        // Service should be reused on subsequent calls
        #expect(interpretationServiceCallCount == 1)
    }

    // MARK: interpret – error propagation

    @Test
    func interpretReturnsFailureWhenServiceThrows() async {
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                MockNotesAssistantService(
                    capabilityState: .available,
                    response: NotesAssistantResponse(text: "", referencedNoteIDs: [])
                )
            },
            interpretationFactory: {
                ThrowingVoiceCaptureInterpretationService()
            }
        )

        let result = await coordinator.interpret(transcript: "throw an error", locale: .current)

        switch result {
        case .success:
            Issue.record("Expected failure from throwing service.")
        case let .failure(error):
            #expect(error is VoiceCaptureInterpretationError)
        }
    }
}

// MARK: - Private Test Doubles

@MainActor
private final class ThrowingNotesAssistantService: NotesAssistantService {
    var capabilityState: AssistantCapabilityState { .available }
    var status: NotesAssistantStatus? { nil }

    func prewarm() {}
    func resetConversation() {}

    func process(_ input: String) async throws -> NotesAssistantResponse {
        throw NotesAssistantError.unavailable("Simulated process failure.")
    }
}

private final class ThrowingVoiceCaptureInterpretationService: VoiceCaptureInterpretationService, @unchecked Sendable {
    var capabilityState: AssistantCapabilityState { .available }

    func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        throw VoiceCaptureInterpretationError.unavailable("Simulated interpret failure.")
    }
}

@MainActor
private final class MockNotesAssistantService: NotesAssistantService {
    let capabilityState: AssistantCapabilityState
    private let response: NotesAssistantResponse

    init(capabilityState: AssistantCapabilityState, response: NotesAssistantResponse) {
        self.capabilityState = capabilityState
        self.response = response
    }

    func prewarm() {}
    func resetConversation() {}

    func process(_ input: String) async throws -> NotesAssistantResponse {
        if case let .unavailable(reason) = capabilityState {
            throw NotesAssistantError.unavailable(reason)
        }
        return response
    }
}

private final class MockVoiceCaptureInterpretationService: VoiceCaptureInterpretationService, @unchecked Sendable {
    let capabilityState: AssistantCapabilityState
    private let result: VoiceCaptureInterpretation

    init(
        capabilityState: AssistantCapabilityState = .available,
        result: VoiceCaptureInterpretation = VoiceCaptureInterpretation(
            intent: .assistantCommand,
            normalizedText: "show my shopping list"
        )
    ) {
        self.capabilityState = capabilityState
        self.result = result
    }

    func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        if case let .unavailable(reason) = capabilityState {
            throw VoiceCaptureInterpretationError.unavailable(reason)
        }
        return result
    }
}

#endif
