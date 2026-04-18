import Foundation
import SecondBrainDomain
#if canImport(WatchConnectivity)
import WatchConnectivity

#if os(watchOS)
private let companionRelayTimeout: TimeInterval = 10

package protocol WCSessionProtocol: AnyObject {
    var delegate: (any WCSessionDelegate)? { get set }
    var activationState: WCSessionActivationState { get }
    var isReachable: Bool { get }

    func activate()
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    )
}

extension WCSession: WCSessionProtocol {}

package enum WCSessionAdapter {
    package static func defaultSession() -> (any WCSessionProtocol)? {
        WCSession.isSupported() ? WCSession.default : nil
    }
}

private final class RelayContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeoutWorkItem: DispatchWorkItem?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func setTimeout(_ workItem: DispatchWorkItem) {
        lock.lock()
        if continuation == nil {
            lock.unlock()
            workItem.cancel()
            return
        }
        timeoutWorkItem = workItem
        lock.unlock()
    }

    func resume(returning value: Value) {
        guard let continuation = consumeContinuation() else {
            return
        }
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        guard let continuation = consumeContinuation() else {
            return
        }
        continuation.resume(throwing: error)
    }

    private func consumeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }

        let continuation = continuation
        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        return continuation
    }
}

@MainActor
package final class CompanionRelayNotesAssistant: NSObject, NotesAssistantService, VoiceCaptureInterpretationService, WCSessionDelegate {
    private let session: (any WCSessionProtocol)?
    private var conversationID = UUID()

    package init(session: (any WCSessionProtocol)? = WCSessionAdapter.defaultSession()) {
        self.session = session
        super.init()

        self.session?.delegate = self
        self.session?.activate()
    }

    package var capabilityState: AssistantCapabilityState {
        guard let session else {
            return .unavailable(reason: "Companion relay is unavailable on this Apple Watch.")
        }

        guard session.activationState == .activated else {
            return .unavailable(reason: "Connecting to the paired iPhone for Ask Notes.")
        }

        guard session.isReachable else {
            return .unavailable(reason: "Ask Notes on Apple Watch requires the paired iPhone to be nearby and reachable.")
        }

        return .available
    }

    /// Prewarms the service for upcoming use.
    /// - Note: Calling this method performs no work; it is a no-op retained for API compatibility.
    package func prewarm() {}

    /// Resets the identifier that correlates relay requests.
    /// 
    /// Generates and assigns a new `UUID` to `conversationID`.
    package func resetConversation() {
        conversationID = UUID()
    }

    /// Sends the given prompt to the paired iPhone via the companion relay and returns the assistant's response.
    /// - Parameters:
    ///   - input: The text prompt to send to Ask Notes on the paired iPhone.
    /// - Returns: The decoded `NotesAssistantResponse` returned by the paired iPhone.
    /// - Throws: `NotesAssistantError.unavailable` when the companion relay is not configured, not activated, or the paired iPhone is unreachable; or a decoding error if the reply cannot be decoded into a `NotesAssistantResponse`.
    package func process(_ input: String) async throws -> NotesAssistantResponse {
        if case let .unavailable(reason) = capabilityState {
            throw NotesAssistantError.unavailable(reason)
        }
        let session = session!

        return try await withCheckedThrowingContinuation { continuation in
            let relayContinuation = RelayContinuation(continuation)
            let timeout = DispatchWorkItem {
                relayContinuation.resume(
                    throwing: NotesAssistantError.unavailable(
                        "Ask Notes on Apple Watch timed out waiting for the paired iPhone."
                    )
                )
            }
            relayContinuation.setTimeout(timeout)
            DispatchQueue.main.asyncAfter(deadline: .now() + companionRelayTimeout, execute: timeout)

            session.sendMessage(
                CompanionRelayMessageCodec.assistantRequest(id: conversationID, prompt: input),
                replyHandler: { reply in
                    do {
                        relayContinuation.resume(returning: try CompanionRelayMessageCodec.decodeAssistantResponse(reply))
                    } catch {
                        relayContinuation.resume(throwing: error)
                    }
                },
                errorHandler: { error in
                    relayContinuation.resume(
                        throwing: NotesAssistantError.unavailable(
                            "Ask Notes on Apple Watch could not reach the paired iPhone. \(error.localizedDescription)"
                        )
                    )
                }
            )
        }
    }

    /// Sends the transcript to the paired iPhone via the companion relay and returns the interpreted voice command.
    /// - Parameters:
    ///   - transcript: The captured speech text to interpret.
    ///   - locale: The locale to use when interpreting the transcript.
    /// - Returns: A `VoiceCaptureInterpretation` representing the interpreted command and associated metadata.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable` when the companion relay is not configured, when the capability is unavailable (with the provided reason), when the paired iPhone is not available, or when the message could not be delivered to the paired iPhone (the error message includes delivery failure details).
    package func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        if case let .unavailable(reason) = capabilityState {
            throw VoiceCaptureInterpretationError.unavailable(reason)
        }
        guard let session else {
            throw VoiceCaptureInterpretationError.unavailable("Companion relay is unavailable on this Apple Watch.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let relayContinuation = RelayContinuation(continuation)
            let timeout = DispatchWorkItem {
                relayContinuation.resume(
                    throwing: VoiceCaptureInterpretationError.unavailable(
                        "Voice command routing on Apple Watch timed out waiting for the paired iPhone."
                    )
                )
            }
            relayContinuation.setTimeout(timeout)
            DispatchQueue.main.asyncAfter(deadline: .now() + companionRelayTimeout, execute: timeout)

            session.sendMessage(
                CompanionRelayMessageCodec.voiceInterpretationRequest(
                    id: conversationID,
                    transcript: transcript,
                    locale: locale
                ),
                replyHandler: { reply in
                    do {
                        relayContinuation.resume(
                            returning: try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(reply)
                        )
                    } catch {
                        relayContinuation.resume(throwing: error)
                    }
                },
                errorHandler: { error in
                    relayContinuation.resume(
                        throwing: VoiceCaptureInterpretationError.unavailable(
                            "Voice command routing on Apple Watch could not reach the paired iPhone. \(error.localizedDescription)"
                        )
                    )
                }
            )
        }
    }

    /// Called when the watch connectivity session finishes activation; intentionally does nothing.
    /// - Parameters:
    ///   - session: The `WCSession` whose activation completed.
    ///   - activationState: The resulting `WCSessionActivationState` for the session.
    ///   - error: An optional error that occurred during activation, if any.
    package nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {}

    /// Handles changes to the `WCSession` reachability state; this implementation is intentionally a no-op.
    package nonisolated func sessionReachabilityDidChange(_ session: WCSession) {}
}
#endif
#endif
