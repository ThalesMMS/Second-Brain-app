import Observation
import SwiftData
import SwiftUI

@available(iOS 17.0, watchOS 10.0, *)
public struct AppStartupFailure: Equatable, Sendable {
    public let title: String
    public let message: String
    public let diagnostics: String

    public init(title: String, message: String, diagnostics: String) {
        self.title = title
        self.message = message
        self.diagnostics = diagnostics
    }

    init(error: any Error) {
        if let bootstrapError = error as? AppGraphBootstrapError {
            self.init(
                title: "Second Brain Is Unavailable",
                message: bootstrapError.summary,
                diagnostics: bootstrapError.details
            )
            return
        }

        let localizedDescription = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            title: "Second Brain Is Unavailable",
            message: "Second Brain couldn't finish startup.",
            diagnostics: localizedDescription.isEmpty ? String(describing: error) : localizedDescription
        )
    }
}

@available(iOS 17.0, watchOS 10.0, *)
public enum AppStartupState {
    case bootstrapping
    case ready(AppGraph)
    case failed(AppStartupFailure)
}

@available(iOS 17.0, watchOS 10.0, *)
@MainActor
@Observable
public final class AppStartupCoordinator {
    public typealias Bootstrap = () async throws -> AppGraph

    public private(set) var state: AppStartupState = .bootstrapping

    private let bootstrap: Bootstrap
    private var hasAttemptedBootstrap = false
    private var isBootstrapping = false

    public init(bootstrap: @escaping Bootstrap = { try await AppGraph.makeLiveForStartup() }) {
        self.bootstrap = bootstrap
    }

    /// Initiates the app bootstrap process if a bootstrap has not already been attempted.
    /// 
    /// If a previous bootstrap attempt has already been made, this method does nothing.
    public func startIfNeeded() async {
        guard !hasAttemptedBootstrap else {
            return
        }

        await performBootstrap()
    }

    /// Forces the coordinator to perform a bootstrap attempt regardless of prior attempts.
    ///
    /// If a bootstrap is already in progress this call returns immediately; otherwise it triggers a new bootstrap and updates the coordinator's `state` to reflect success (`.ready`) or failure (`.failed`).
    public func retry() async {
        await performBootstrap()
    }

    /// Attempts to run the injected bootstrap closure and updates the coordinator's state to reflect progress and result.
    /// 
    /// If a bootstrap is already in progress this returns immediately. Marks that a bootstrap has been attempted and manages the `isBootstrapping` flag for the duration of the operation. On success sets `state` to `.ready` with the created `AppGraph`; on error sets `state` to `.failed` with an `AppStartupFailure` constructed from the thrown error.
    private func performBootstrap() async {
        guard !isBootstrapping else {
            return
        }

        hasAttemptedBootstrap = true
        isBootstrapping = true
        state = .bootstrapping

        defer {
            isBootstrapping = false
        }

        do {
            state = .ready(try await bootstrap())
        } catch {
            state = .failed(AppStartupFailure(error: error))
        }
    }
}

@available(iOS 17.0, watchOS 10.0, *)
public struct AppStartupContainerView<ReadyContent: View>: View {
    @Bindable private var coordinator: AppStartupCoordinator
    private let readyContent: (AppGraph) -> ReadyContent

    public init(
        coordinator: AppStartupCoordinator,
        @ViewBuilder readyContent: @escaping (AppGraph) -> ReadyContent
    ) {
        self.coordinator = coordinator
        self.readyContent = readyContent
    }

    public var body: some View {
        Group {
            switch coordinator.state {
            case .bootstrapping:
                ProgressView("Starting Second Brain...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .ready(graph):
                readyContent(graph)
                    .modelContainer(graph.modelContainer)
            case let .failed(failure):
                AppStartupFailureView(failure: failure) {
                    Task {
                        await coordinator.retry()
                    }
                }
            }
        }
        .task {
            await coordinator.startIfNeeded()
        }
    }
}

@available(iOS 17.0, watchOS 10.0, *)
public struct AppStartupFailureView: View {
    private let failure: AppStartupFailure
    private let onRetry: () -> Void

    public init(failure: AppStartupFailure, onRetry: @escaping () -> Void) {
        self.failure = failure
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text(failure.title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(failure.message)
                .font(.body)
                .multilineTextAlignment(.center)

            Text(failure.diagnostics)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
