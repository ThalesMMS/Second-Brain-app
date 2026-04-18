import Foundation
import SecondBrainDomain
#if canImport(WatchConnectivity)
import WatchConnectivity

#if os(iOS)
@MainActor
package final class CompanionRelayNotesAssistantHostCoordinator {
    private let assistantFactory: @MainActor () -> any NotesAssistantService
    private let interpretationFactory: @MainActor () -> any VoiceCaptureInterpretationService
    private var assistants: [UUID: any NotesAssistantService] = [:]
    private var interpretationService: (any VoiceCaptureInterpretationService)?
    private var conversationOrder: [UUID] = []
    private let maximumCachedConversations = 8

    init(
        assistantFactory: @escaping @MainActor () -> any NotesAssistantService,
        interpretationFactory: @escaping @MainActor () -> any VoiceCaptureInterpretationService
    ) {
        self.assistantFactory = assistantFactory
        self.interpretationFactory = interpretationFactory
    }

    /// Processes a text prompt using the assistant associated with the given conversation.
    /// - Parameters:
    ///   - prompt: The user prompt to be processed by the assistant.
    ///   - conversationID: The UUID identifying the conversation; used to select or create a cached assistant.
    /// - Returns: A `Result` containing a `NotesAssistantResponse` on success, or an `Error` on failure. If the assistant's capability is unavailable the result is `.failure(NotesAssistantError.unavailable(_))`.
    func process(prompt: String, conversationID: UUID) async -> Result<NotesAssistantResponse, Error> {
        let assistant = assistant(for: conversationID)
        if case let .unavailable(reason) = assistant.capabilityState {
            return .failure(NotesAssistantError.unavailable(reason))
        }

        do {
            return .success(try await assistant.process(prompt))
        } catch {
            return .failure(error)
        }
    }

    /// Interprets a spoken transcript into a `VoiceCaptureInterpretation` using a lazily-created interpretation service.
    ///
    /// If the interpretation service reports an unavailable capability state, the result is a failure containing
    /// `VoiceCaptureInterpretationError.unavailable(reason)`.
    /// - Parameters:
    ///   - transcript: The spoken text to interpret.
    ///   - locale: The locale to use when interpreting the transcript.
    /// - Returns: A `Result` whose success case contains the interpreted `VoiceCaptureInterpretation`, or whose failure case contains the underlying `Error` (including `VoiceCaptureInterpretationError.unavailable` when the service is not available).
    func interpret(transcript: String, locale: Locale) async -> Result<VoiceCaptureInterpretation, Error> {
        let interpretationService = interpretationService ?? {
            let service = interpretationFactory()
            self.interpretationService = service
            return service
        }()

        if case let .unavailable(reason) = interpretationService.capabilityState {
            return .failure(VoiceCaptureInterpretationError.unavailable(reason))
        }

        do {
            return .success(try await interpretationService.interpret(transcript: transcript, locale: locale))
        } catch {
            return .failure(error)
        }
    }

    /// Obtains the cached or newly created `NotesAssistantService` for the given conversation ID.
    ///
    /// If an assistant already exists for `conversationID`, that instance is returned and the conversation's
    /// usage timestamp is updated. If none exists, a new assistant is created, cached, the conversation is
    /// marked as recently used, and the cache is pruned to enforce the maximum cached conversations limit.
    /// - Parameters:
    ///   - conversationID: The UUID identifying the conversation used as the cache key.
    /// - Returns: The `NotesAssistantService` instance associated with `conversationID`.
    private func assistant(for conversationID: UUID) -> any NotesAssistantService {
        if let existing = assistants[conversationID] {
            touchConversation(conversationID)
            return existing
        }

        let assistant = assistantFactory()
        assistants[conversationID] = assistant
        touchConversation(conversationID)
        pruneIfNeeded()
        return assistant
    }

    /// Marks the given conversation ID as most recently used by moving it to the end of `conversationOrder`.
    /// - Parameter id: The conversation `UUID` to touch (move to the most-recently-used position).
    private func touchConversation(_ id: UUID) {
        conversationOrder.removeAll { $0 == id }
        conversationOrder.append(id)
    }

    /// Ensures the cached assistants do not exceed the maximum by evicting oldest conversations.
    /// 
    /// Removes oldest conversation IDs from `conversationOrder` and deletes their corresponding entries from `assistants` until `conversationOrder.count` is less than or equal to `maximumCachedConversations`.
    private func pruneIfNeeded() {
        while conversationOrder.count > maximumCachedConversations {
            let removedID = conversationOrder.removeFirst()
            assistants.removeValue(forKey: removedID)
        }
    }
}

@MainActor
package final class CompanionRelayNotesAssistantHost: NSObject, WCSessionDelegate {
    private let session: WCSession?
    private let coordinator: CompanionRelayNotesAssistantHostCoordinator

    package init(
        assistantFactory: @escaping @MainActor () -> any NotesAssistantService,
        interpretationFactory: @escaping @MainActor () -> any VoiceCaptureInterpretationService
    ) {
        self.coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: assistantFactory,
            interpretationFactory: interpretationFactory
        )
        if WCSession.isSupported() {
            let session = WCSession.default
            self.session = session
        } else {
            self.session = nil
        }
        super.init()

        session?.delegate = self
        session?.activate()
    }

    /// Handles completion of a WCSession activation. This implementation intentionally performs no action.
    /// - Parameters:
    ///   - session: The `WCSession` whose activation completed.
    ///   - activationState: The resulting `WCSessionActivationState`.
    ///   - error: An optional error that occurred during activation.
    package nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {}

    /// Called when the watch connectivity session transitions to an inactive state; intentionally does nothing.
    /// - Parameter session: The `WCSession` instance that became inactive.
    package nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Re-activates the WatchConnectivity session after it has been deactivated.
    /// - Parameter session: The deactivated `WCSession` to reactivate.
    package nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Called when the watch connectivity session's reachability changes; intentionally does nothing.
    package nonisolated func sessionReachabilityDidChange(_ session: WCSession) {}

    /// Handles incoming WatchConnectivity messages by decoding them as either an assistant request or a voice-interpretation request and replying with a corresponding success or error payload.
    ///
    /// If the message decodes as an assistant request, the coordinator's `process(prompt:conversationID:)` is invoked on the main actor and the reply contains either an assistant response or an error payload. If the message decodes as a voice-interpretation request, the coordinator's `interpret(transcript:locale:)` is invoked on the main actor and the reply contains either an interpretation response or an error payload. If decoding fails for both request types, an error reply indicating an invalid relay request is sent.
    package nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let request = CompanionRelayMessageCodec.decodeAssistantRequest(message) {
            Task { @MainActor in
                let result = await coordinator.process(prompt: request.prompt, conversationID: request.id)
                switch result {
                case let .success(response):
                    replyHandler(CompanionRelayMessageCodec.assistantResponse(id: request.id, response: response))
                case let .failure(error):
                    replyHandler(
                        CompanionRelayMessageCodec.error(
                            id: request.id,
                            message: error.localizedDescription
                        )
                    )
                }
            }
            return
        }

        if let request = CompanionRelayMessageCodec.decodeVoiceInterpretationRequest(message) {
            Task { @MainActor in
                let locale = Locale(identifier: request.localeIdentifier)
                let result = await coordinator.interpret(transcript: request.transcript, locale: locale)
                switch result {
                case let .success(interpretation):
                    replyHandler(
                        CompanionRelayMessageCodec.voiceInterpretationResponse(
                            id: request.id,
                            interpretation: interpretation
                        )
                    )
                case let .failure(error):
                    replyHandler(
                        CompanionRelayMessageCodec.error(
                            id: request.id,
                            message: error.localizedDescription
                        )
                    )
                }
            }
            return
        }

        replyHandler(CompanionRelayMessageCodec.error(id: nil, message: "The watch sent an invalid relay request."))
    }
}
#endif
#endif