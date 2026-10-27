import ComposableArchitecture
import Foundation
import LabcordShared
import SwiftData
import SwiftUI

/// 실제 앱에는 포함되지 않는 시뮬레이터 검증 진입점입니다.
@main
struct EntryQAApp: App {
    @State private var store: StoreOf<EntryQARoot>
    private let observesEvents: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        observesEvents = arguments.contains("--observe-events")
        let client = EntryQASupport.client(arguments: arguments)
        _store = State(initialValue: Store(initialState: EntryQARoot.State()) {
            EntryQARoot()
        } withDependencies: {
            $0.experimentEntryClient = client
        })
    }

    var body: some Scene {
        WindowGroup {
            ExperimentEntryView(store: store.scope(state: \.entry, action: \.entry))
                .overlay(alignment: .bottomLeading) {
                    if observesEvents {
                        Text(store.lastEvent)
                            .font(.system(size: 8))
                            .accessibilityIdentifier("qa-event")
                    }
                }
        }
    }
}

@Reducer
struct EntryQARoot {
    @ObservableState
    struct State: Equatable {
        var entry = ExperimentEntryFeature.State()
        var lastEvent = ""
    }

    enum Action {
        case entry(ExperimentEntryFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.entry, action: \.entry) { ExperimentEntryFeature() }
        Reduce { state, action in
            switch action {
            case let .entry(.delegate(.experimentCreated(identifier))):
                state.lastEvent = "created:\(identifier.uuidString)"
            case let .entry(.delegate(.experimentSelected(identifier))):
                state.lastEvent = "selected:\(identifier.uuidString)"
            case let .entry(.delegate(.protocolSourceRequested(source))):
                state.lastEvent = "source:\(source.rawValue)"
            case .entry(.delegate(.settingsRequested)):
                state.lastEvent = "settings"
            default:
                break
            }
            return .none
        }
    }
}

private enum EntryQASupport {
    @MainActor
    final class FailureGate {
        var load: Bool
        var save: Bool

        init(arguments: [String]) {
            load = arguments.contains("--fail-first-load")
            save = arguments.contains("--fail-first-save")
        }
    }

    static func client(arguments: [String]) -> ExperimentEntryClient {
        let fixture = arguments.contains("--fixture-home")
        let gate = FailureGate(arguments: arguments)
        let repository = ExperimentEntryRepository {
            let schema = Schema([
                Experiment.self, ExperimentRecord.self, Pause.self, ExperimentStatusEntry.self
            ])
            let configuration: ModelConfiguration
            if fixture {
                configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            } else {
                let directory = URL.applicationSupportDirectory.appending(path: "EntryQAStore")
                if arguments.contains("--reset-store"),
                   FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                configuration = ModelConfiguration(
                    schema: schema, url: directory.appending(path: "entry.store")
                )
            }
            let container = try ModelContainer(for: schema, configurations: configuration)
            if fixture { try seed(container) }
            return container
        }
        return ExperimentEntryClient(
            load: {
                if gate.load {
                    gate.load = false
                    throw ExperimentEntryFeature.Failure.loading
                }
                return try repository.load()
            },
            create: { identifier, date in
                if gate.save {
                    gate.save = false
                    throw ExperimentEntryFeature.Failure.saving
                }
                return try repository.create(id: identifier, at: date)
            }
        )
    }

    private static func seed(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_760_356_800)
        let statuses: [ExperimentStatus] = [
            .inProgress, .paused, .preparing, .preparing, .completed, .completed, .completed
        ]
        for (index, status) in statuses.enumerated() {
            let suffix = String(format: "%012d", index + 1)
            guard let identifier = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") else {
                continue
            }
            context.insert(Experiment(
                id: identifier, title: "실험 제목", createdAt: date, status: status
            ))
        }
        try context.save()
    }
}
