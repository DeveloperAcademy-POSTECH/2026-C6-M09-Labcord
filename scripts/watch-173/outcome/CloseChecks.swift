import Foundation

enum WatchExperimentError: Error { case phoneBusy, invalidState }
struct WatchDefinitiveRejection: Error { let error: WatchExperimentError }
struct WatchExecutionUncertain: Error {}
enum Status { case running, paused }
enum Operation { case pause, complete }
struct WatchExperimentCommand { let requestID = UUID(); let operation: Operation }
struct Experiment { let id: UUID; let status: Status }
struct WatchExperimentSnapshot { let experiment: Experiment }
struct Client {
    func leaveSession(_ id: UUID, _ request: UUID, _ date: Date) throws {}
    func complete(_ id: UUID, _ date: Date) throws {}
}
@MainActor final class Coordinator {
    enum Event { case command(WatchExperimentCommand) }
    var visibleExperimentID: UUID?
    var pendingStartID: UUID?
    var prepareSessionClose: ((WatchExperimentCommand) async throws -> Void)?
    var completions: [UUID: CheckedContinuation<Void, Error>] = [:]
    var commandSubscriber: AsyncStream<Event>.Continuation?
    let client = Client()
    // ACTUAL_CLOSE
}
@main struct Checks {
    @MainActor static func main() async {
        for prepared in [false, true] {
            for definite in [false, true] {
                let coordinator = Coordinator()
                let id = UUID()
                coordinator.visibleExperimentID = id
                if prepared { coordinator.prepareSessionClose = { _ in } }
                let stream = AsyncStream<Coordinator.Event> { coordinator.commandSubscriber = $0 }
                let receiver = Task { @MainActor in
                    for await case let .command(command) in stream {
                        let continuation = coordinator.completions.removeValue(forKey: command.requestID)!
                        if definite { continuation.resume(throwing: WatchDefinitiveRejection(error: .phoneBusy)) }
                        else { continuation.resume(throwing: WatchExperimentError.phoneBusy) }
                        break
                    }
                }
                do {
                    try await coordinator.close(.init(operation: .pause), current: .init(experiment: .init(id: id, status: .running)))
                    fatalError("expected error")
                } catch WatchExperimentError.phoneBusy {
                    precondition(definite && !prepared)
                } catch is WatchExecutionUncertain {
                    precondition(!definite || prepared)
                } catch { fatalError("unexpected error: \(error)") }
                await receiver.value
            }
        }
        print("PASS: close distinguishes proven pre-dispatch rejection from possible effects")
    }
}
