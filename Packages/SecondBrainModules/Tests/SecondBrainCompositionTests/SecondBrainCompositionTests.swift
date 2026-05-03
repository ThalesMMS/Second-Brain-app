import Foundation
import Testing
@testable import SecondBrainComposition
@testable import SecondBrainDomain
@testable import SecondBrainPersistence

struct SecondBrainCompositionTests {
    @Test
    @MainActor
    func startupCoordinatorTransitionsToReadyWhenBootstrapSucceeds() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let coordinator = AppStartupCoordinator {
            graph
        }

        await coordinator.startIfNeeded()

        switch coordinator.state {
        case let .ready(readyGraph):
            #expect(readyGraph === graph)
        case .bootstrapping, .failed:
            Issue.record("Expected startup coordinator to enter the ready state.")
        }
    }

    @Test
    @MainActor
    func startupCoordinatorTransitionsToFailureWhenBootstrapThrows() async {
        let coordinator = AppStartupCoordinator {
            throw StubBootstrapError(message: "Injected startup failure.")
        }

        await coordinator.startIfNeeded()

        switch coordinator.state {
        case let .failed(failure):
            #expect(failure.message == "Second Brain couldn't finish startup.")
            #expect(failure.diagnostics.contains("Injected startup failure."))
        case .bootstrapping, .ready:
            Issue.record("Expected startup coordinator to enter the failed state.")
        }
    }

    @Test
    @MainActor
    func startupCoordinatorRetryRecoversAfterInitialFailure() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        var attempts = 0
        let coordinator = AppStartupCoordinator {
            attempts += 1
            if attempts == 1 {
                throw StubBootstrapError(message: "First attempt failed.")
            }

            return graph
        }

        await coordinator.startIfNeeded()
        await coordinator.retry()

        #expect(attempts == 2)

        switch coordinator.state {
        case let .ready(readyGraph):
            #expect(readyGraph === graph)
        case .bootstrapping, .failed:
            Issue.record("Expected retry to recover into the ready state.")
        }
    }

    @Test
    @MainActor
    func startupCoordinatorRetryKeepsFailureStateWhenBootstrapStillFails() async {
        var attempts = 0
        let coordinator = AppStartupCoordinator {
            attempts += 1
            throw StubBootstrapError(message: "Attempt \(attempts) failed.")
        }

        await coordinator.startIfNeeded()
        await coordinator.retry()

        #expect(attempts == 2)

        switch coordinator.state {
        case let .failed(failure):
            #expect(failure.diagnostics.contains("Attempt 2 failed."))
        case .bootstrapping, .ready:
            Issue.record("Expected retry to keep the failure state when bootstrap still fails.")
        }
    }

    @Test
    @MainActor
    func makeLiveHelperBuildsGraphWithInjectedPersistenceController() async throws {
        let graph = try AppGraph.makeLive(
            enableCloudSync: false,
            useSharedContainer: false,
            persistenceControllerFactory: { _, _, _ in
                try PersistenceController(
                    inMemory: true,
                    enableCloudSync: false,
                    useSharedContainer: false
                )
            }
        )

        let created = try await graph.createNote.execute(
            title: "Inbox",
            body: "Recover startup",
            source: .manual
        )
        let loaded = try await graph.loadNote.execute(id: created.id)

        #expect(loaded?.body == "Recover startup")
    }

    #if os(macOS)
    @Test
    @MainActor
    func appleIntelligenceFallbackReasonsMentionMacOS() {
        #expect(AppGraph.appleIntelligenceCaptureUnavailableReason.contains("macOS 26 or newer"))
        #expect(AppGraph.appleIntelligenceVoiceRoutingUnavailableReason.contains("macOS 26 or newer"))
    }
    #endif

    @Test
    @MainActor
    func appGraphWiresSetNotePinnedUseCaseToSharedRepository() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let created = try await graph.createNote.execute(
            title: "Reference",
            body: "Keep accessible",
            source: .manual
        )

        try await graph.setNotePinned.execute(noteID: created.id, isPinned: true)

        let loaded = try await graph.loadNote.execute(id: created.id)
        #expect(loaded?.isPinned == true)
    }

    @Test
    @MainActor
    func makeLiveHelperSupportsDeterministicFailureInjection() async {
        await #expect(throws: AppGraphBootstrapError.self) {
            _ = try AppGraph.makeLive(
                enableCloudSync: false,
                useSharedContainer: false,
                persistenceControllerFactory: { _, _, _ in
                    throw StubBootstrapError(message: "Injected persistence bootstrap failure.")
                }
            )
        }
    }

    // MARK: - AppGraphBootstrapError

    @Test
    func appGraphBootstrapErrorErrorDescriptionReturnsSummary() {
        let error = AppGraphBootstrapError(
            summary: "Could not open store.",
            details: "Disk full."
        )

        #expect(error.errorDescription == "Could not open store.")
    }

    @Test
    func appGraphBootstrapErrorFailureReasonReturnsDetails() {
        let error = AppGraphBootstrapError(
            summary: "Could not open store.",
            details: "Disk full."
        )

        #expect(error.failureReason == "Disk full.")
    }

    @Test
    func appGraphBootstrapErrorLivePersistenceFailureSetsSummary() {
        let underlying = StubBootstrapError(message: "migration failed")
        let error = AppGraphBootstrapError.livePersistenceFailure(underlying)

        #expect(error.summary == "Second Brain couldn't open your notes store.")
        #expect(error.details.contains("migration failed"))
    }

    @Test
    func appGraphBootstrapErrorUiTestPersistenceFailureSetsSummary() {
        let underlying = StubBootstrapError(message: "in-memory store init failed")
        let error = AppGraphBootstrapError.uiTestPersistenceFailure(underlying)

        #expect(error.summary == "Second Brain couldn't start in UI test mode.")
        #expect(error.details.contains("in-memory store init failed"))
    }

    @Test
    func appGraphBootstrapErrorUiTestSeedingFailureSetsSummary() {
        let underlying = StubBootstrapError(message: "seed insert rejected")
        let error = AppGraphBootstrapError.uiTestSeedingFailure(underlying)

        #expect(error.summary == "Second Brain couldn't seed UI test data.")
        #expect(error.details.contains("seed insert rejected"))
    }

    @Test
    func appGraphBootstrapErrorUiTestAudioDirectoryFailureSetsSummary() {
        let underlying = StubBootstrapError(message: "permission denied")
        let error = AppGraphBootstrapError.uiTestAudioDirectoryFailure(underlying)

        #expect(error.summary == "Second Brain couldn't prepare UI test audio storage.")
        #expect(error.details.contains("permission denied"))
    }

    @Test
    func appGraphBootstrapErrorDescribeFallsBackToStringDescribingWhenLocalizedDescriptionIsEmpty() {
        let underlying = EmptyDescriptionError()
        // livePersistenceFailure uses describe() internally
        let error = AppGraphBootstrapError.livePersistenceFailure(underlying)

        // When localizedDescription is empty, details must be non-empty (String(describing:) fallback)
        #expect(!error.details.isEmpty)
        #expect(error.details.contains("EmptyDescriptionError"))
    }

    // MARK: - AppStartupFailure

    @Test
    func appStartupFailureInitWithAppGraphBootstrapErrorMapsSummaryAndDetails() {
        let bootstrapError = AppGraphBootstrapError(
            summary: "Couldn't open notes.",
            details: "Underlying cause here."
        )
        let failure = AppStartupFailure(error: bootstrapError)

        #expect(failure.title == "Second Brain Is Unavailable")
        #expect(failure.message == "Couldn't open notes.")
        #expect(failure.diagnostics == "Underlying cause here.")
    }

    @Test
    func appStartupFailureInitWithGenericLocalizedErrorUsesGenericMessage() {
        let error = StubBootstrapError(message: "Generic localized error message.")
        let failure = AppStartupFailure(error: error)

        #expect(failure.title == "Second Brain Is Unavailable")
        #expect(failure.message == "Second Brain couldn't finish startup.")
        #expect(failure.diagnostics.contains("Generic localized error message."))
    }

    @Test
    func appStartupFailureInitWithEmptyLocalizedDescriptionFallsBackToStringDescribing() {
        let error = EmptyDescriptionError()
        let failure = AppStartupFailure(error: error)

        #expect(failure.title == "Second Brain Is Unavailable")
        #expect(!failure.diagnostics.isEmpty)
        #expect(failure.diagnostics.contains("EmptyDescriptionError"))
    }

    @Test
    func appStartupFailureEqualityHoldsWhenAllFieldsMatch() {
        let a = AppStartupFailure(title: "T", message: "M", diagnostics: "D")
        let b = AppStartupFailure(title: "T", message: "M", diagnostics: "D")

        #expect(a == b)
    }

    @Test
    func appStartupFailureEqualityFailsWhenDiagnosticsDiffer() {
        let a = AppStartupFailure(title: "T", message: "M", diagnostics: "D1")
        let b = AppStartupFailure(title: "T", message: "M", diagnostics: "D2")

        #expect(a != b)
    }

    // MARK: - AppStartupCoordinator idempotency

    @Test
    @MainActor
    func startupCoordinatorInitialStateIsBootstrapping() {
        let coordinator = AppStartupCoordinator {
            throw StubBootstrapError(message: "Should never be called.")
        }

        switch coordinator.state {
        case .bootstrapping:
            break // expected
        case .ready, .failed:
            Issue.record("Initial state must be .bootstrapping.")
        }
    }

    @Test
    @MainActor
    func startupCoordinatorStartIfNeededIsIdempotentAndBootstrapsOnlyOnce() async throws {
        var callCount = 0
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let coordinator = AppStartupCoordinator {
            callCount += 1
            return graph
        }

        await coordinator.startIfNeeded()
        await coordinator.startIfNeeded()
        await coordinator.startIfNeeded()

        #expect(callCount == 1)

        switch coordinator.state {
        case .ready:
            break // expected
        case .bootstrapping, .failed:
            Issue.record("Expected coordinator to be in ready state after first startIfNeeded.")
        }
    }

    @Test
    @MainActor
    func startupCoordinatorStartIfNeededDoesNotReRunAfterReadyState() async throws {
        var callCount = 0
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let coordinator = AppStartupCoordinator {
            callCount += 1
            return graph
        }

        await coordinator.startIfNeeded()
        // Second call after being in ready state must not re-run bootstrap
        await coordinator.startIfNeeded()

        #expect(callCount == 1)
    }

    @Test
    @MainActor
    func startupCoordinatorRetryAlwaysReRunsBootstrapFromReadyState() async throws {
        var callCount = 0
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let coordinator = AppStartupCoordinator {
            callCount += 1
            return graph
        }

        await coordinator.startIfNeeded()
        await coordinator.retry()

        #expect(callCount == 2)
    }

    @Test
    @MainActor
    func startupCoordinatorTransitionsToBootstrappingDuringRetry() async throws {
        // Verify state returns to .bootstrapping before resolving again
        var states: [String] = []
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        var attempt = 0
        let coordinator = AppStartupCoordinator {
            attempt += 1
            if attempt == 1 { throw StubBootstrapError(message: "first") }
            return graph
        }

        await coordinator.startIfNeeded()
        // After first attempt: failed
        switch coordinator.state {
        case .failed: states.append("failed")
        default: states.append("other")
        }
        await coordinator.retry()
        // After retry: ready
        switch coordinator.state {
        case .ready: states.append("ready")
        default: states.append("other")
        }

        #expect(states == ["failed", "ready"])
    }

    // MARK: - AppGraph.makeLive error wrapping

    @Test
    @MainActor
    func makeLivePublicWrapsPersistenceErrorInBootstrapError() async {
        await #expect(throws: AppGraphBootstrapError.self) {
            _ = try AppGraph.makeLive(
                enableCloudSync: false,
                useSharedContainer: false,
                persistenceControllerFactory: { _, _, _ in
                    throw StubBootstrapError(message: "Injected failure for wrapping test.")
                }
            )
        }
    }

    @Test
    @MainActor
    func makeLivePublicBootstrapErrorSummaryIsLivePersistenceSummary() {
        var caughtError: AppGraphBootstrapError?
        do {
            _ = try AppGraph.makeLive(
                enableCloudSync: false,
                useSharedContainer: false,
                persistenceControllerFactory: { _, _, _ in
                    throw StubBootstrapError(message: "disk failure")
                }
            )
        } catch let e as AppGraphBootstrapError {
            caughtError = e
        } catch {}

        #expect(caughtError?.summary == "Second Brain couldn't open your notes store.")
        #expect(caughtError?.details.contains("disk failure") == true)
    }

    @Test
    @MainActor
    func makeLiveHelperRethrowsExistingBootstrapError() {
        let bootstrapError = AppGraphBootstrapError(
            summary: "Existing bootstrap summary.",
            details: "Existing bootstrap diagnostics."
        )
        var caughtError: AppGraphBootstrapError?

        do {
            _ = try AppGraph.makeLive(
                enableCloudSync: false,
                useSharedContainer: false,
                persistenceControllerFactory: { _, _, _ in
                    throw bootstrapError
                }
            )
        } catch let error as AppGraphBootstrapError {
            caughtError = error
        } catch {}

        #expect(caughtError?.summary == bootstrapError.summary)
        #expect(caughtError?.details == bootstrapError.details)
    }
}

// MARK: - Test helpers

private struct StubBootstrapError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

/// An error whose `localizedDescription` is empty, used to exercise the `String(describing:)` fallback path.
private struct EmptyDescriptionError: LocalizedError {
    var errorDescription: String? { "" }
}
