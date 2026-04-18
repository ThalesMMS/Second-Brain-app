import Foundation
import SecondBrainDomain
#if canImport(WatchConnectivity)

package enum CompanionRelayRequestKind: String {
    case assistant
    case voiceInterpretation
}

package struct CompanionRelayAssistantRequest {
    let id: UUID
    let prompt: String
}

package struct CompanionRelayInterpretationRequest {
    let id: UUID
    let transcript: String
    let localeIdentifier: String
}

package enum CompanionRelayMessageCodec {
    private static let kindKey = "kind"
    private static let idKey = "id"
    private static let promptKey = "prompt"
    private static let transcriptKey = "transcript"
    private static let localeIdentifierKey = "localeIdentifier"
    private static let textKey = "text"
    private static let referencedNoteIDsKey = "referencedNoteIDs"
    private static let interactionKey = "interaction"
    private static let intentKey = "intent"
    private static let normalizedTextKey = "normalizedText"
    private static let errorKey = "error"

    /// Builds a dictionary payload for an assistant relay request.
    /// - Parameters:
    ///   - id: The request UUID.
    ///   - prompt: The assistant prompt text.
    /// - Returns: A dictionary containing `kind` set to `"assistant"`, `id` as the UUID string, and `prompt` as provided.
    static func assistantRequest(id: UUID, prompt: String) -> [String: Any] {
        [
            kindKey: CompanionRelayRequestKind.assistant.rawValue,
            idKey: id.uuidString,
            promptKey: prompt
        ]
    }

    /// Builds a voice interpretation request payload dictionary for the companion relay protocol.
    /// - Parameters:
    ///   - id: The request UUID.
    ///   - transcript: The captured transcript text.
    ///   - locale: The locale whose identifier will be included as `localeIdentifier`.
    /// - Returns: A dictionary containing `kind` = `"voiceInterpretation"`, `id` (UUID string), `transcript`, and `localeIdentifier`.
    static func voiceInterpretationRequest(
        id: UUID,
        transcript: String,
        locale: Locale
    ) -> [String: Any] {
        [
            kindKey: CompanionRelayRequestKind.voiceInterpretation.rawValue,
            idKey: id.uuidString,
            transcriptKey: transcript,
            localeIdentifierKey: locale.identifier
        ]
    }

    /// Parses a dictionary-encoded assistant relay request message.
    /// - Parameter message: A dictionary representation of a relay message.
    /// - Returns: `CompanionRelayAssistantRequest` if the dictionary contains a valid assistant request payload (including a parsable UUID and a prompt), `nil` otherwise.
    static func decodeAssistantRequest(_ message: [String: Any]) -> CompanionRelayAssistantRequest? {
        guard message[kindKey] as? String == CompanionRelayRequestKind.assistant.rawValue else {
            return nil
        }
        guard let idString = message[idKey] as? String,
              let id = UUID(uuidString: idString),
              let prompt = message[promptKey] as? String else {
            return nil
        }

        return CompanionRelayAssistantRequest(id: id, prompt: prompt)
    }

    /// Parses a voice-interpretation relay request from a message dictionary.
    /// - Parameters:
    ///   - message: A dictionary containing the relay payload. Expected keys: `"kind"`, `"id"` (UUID string), `"transcript"`, and `"localeIdentifier"`.
    /// - Returns: A `CompanionRelayInterpretationRequest` populated from the payload on success; `nil` if the `kind` is not `"voiceInterpretation"` or any required field is missing or invalid.
    static func decodeVoiceInterpretationRequest(_ message: [String: Any]) -> CompanionRelayInterpretationRequest? {
        guard message[kindKey] as? String == CompanionRelayRequestKind.voiceInterpretation.rawValue else {
            return nil
        }
        guard let idString = message[idKey] as? String,
              let id = UUID(uuidString: idString),
              let transcript = message[transcriptKey] as? String,
              let localeIdentifier = message[localeIdentifierKey] as? String else {
            return nil
        }

        return CompanionRelayInterpretationRequest(
            id: id,
            transcript: transcript,
            localeIdentifier: localeIdentifier
        )
    }

    /// Builds a companion-relay payload dictionary for an assistant response.
    /// - Parameters:
    ///   - id: The UUID identifying the original request/response; included as a UUID string under the `id` key.
    ///   - response: The `NotesAssistantResponse` whose properties are encoded into the payload.
    /// - Returns: A dictionary containing:
    ///   - `id`: the `id` as a UUID string,
    ///   - `text`: the assistant response text,
    ///   - `referencedNoteIDs`: an array of UUID strings for referenced notes,
    ///   - `interaction`: the interaction state raw value.
    static func assistantResponse(id: UUID, response: NotesAssistantResponse) -> [String: Any] {
        [
            idKey: id.uuidString,
            textKey: response.text,
            referencedNoteIDsKey: response.referencedNoteIDs.map(\.uuidString),
            interactionKey: response.interaction.rawValue
        ]
    }

    /// Builds a dictionary payload for a voice interpretation response.
    /// - Parameters:
    ///   - id: The UUID of the original request; included as a UUID string under the `id` key.
    ///   - interpretation: The interpretation result whose `intent` and `normalizedText` are included.
    /// - Returns: A dictionary containing `id` (UUID string), `intent` (the interpretation's intent raw value), and `normalizedText` (the interpretation's normalized text).
    static func voiceInterpretationResponse(
        id: UUID,
        interpretation: VoiceCaptureInterpretation
    ) -> [String: Any] {
        [
            idKey: id.uuidString,
            intentKey: interpretation.intent.rawValue,
            normalizedTextKey: interpretation.normalizedText
        ]
    }

    /// Builds an error payload dictionary for companion relay responses.
    /// - Parameters:
    ///   - id: Optional request identifier to include in the payload; included as a UUID string when non-`nil`.
    ///   - message: Human-readable error message to include under the `error` key.
    /// - Returns: A dictionary containing an `error` entry with `message` and, when `id` is provided, an `id` entry with the UUID string.
    static func error(id: UUID?, message: String) -> [String: Any] {
        var payload: [String: Any] = [
            errorKey: message
        ]
        if let id {
            payload[idKey] = id.uuidString
        }
        return payload
    }

    /// Decodes a companion response payload into a `NotesAssistantResponse`.
    /// - Parameter message: A dictionary payload received from the companion containing response fields (e.g. `text`, optional `referencedNoteIDs`, optional `interaction`, optional `error`).
    /// - Returns: A `NotesAssistantResponse` populated with `text`, an array of parsed `UUID` values for `referencedNoteIDs` (invalid UUID strings are dropped), and the resolved `interaction` state (defaults to `.none`).
    /// - Throws: `NotesAssistantError.unavailable` if the payload contains an `error` string or if the required `text` field is missing or not a valid `String`.
    static func decodeAssistantResponse(_ message: [String: Any]) throws -> NotesAssistantResponse {
        if let errorMessage = message[errorKey] as? String {
            throw NotesAssistantError.unavailable(errorMessage)
        }

        guard let text = message[textKey] as? String else {
            throw NotesAssistantError.unavailable("The paired iPhone returned an invalid response.")
        }

        let ids = (message[referencedNoteIDsKey] as? [String] ?? []).compactMap(UUID.init(uuidString:))
        let interaction = NotesAssistantInteractionState(
            rawValue: (message[interactionKey] as? String) ?? ""
        ) ?? .none
        return NotesAssistantResponse(text: text, referencedNoteIDs: ids, interaction: interaction)
    }

    /// Parses a voice-interpretation response payload into a `VoiceCaptureInterpretation`.
    /// - Parameters:
    ///   - message: The dictionary payload received from the companion device; expected to contain either an `error` string or the `intent` and `normalizedText` fields.
    /// - Returns: A `VoiceCaptureInterpretation` constructed from the `intent` and `normalizedText` values in `message`.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable` with the companion-provided error message if `message["error"]` is present, or with a generic message if required fields are missing or invalid.
    static func decodeVoiceInterpretationResponse(
        _ message: [String: Any]
    ) throws -> VoiceCaptureInterpretation {
        if let errorMessage = message[errorKey] as? String {
            throw VoiceCaptureInterpretationError.unavailable(errorMessage)
        }

        guard let intentRawValue = message[intentKey] as? String,
              let intent = VoiceCaptureIntent(rawValue: intentRawValue),
              let normalizedText = message[normalizedTextKey] as? String else {
            throw VoiceCaptureInterpretationError.unavailable("The paired iPhone returned an invalid voice interpretation.")
        }

        return VoiceCaptureInterpretation(intent: intent, normalizedText: normalizedText)
    }
}
#endif
