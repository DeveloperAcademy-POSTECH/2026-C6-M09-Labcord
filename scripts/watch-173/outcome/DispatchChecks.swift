import Foundation

enum WatchExperimentError: Error { case phoneBusy }
struct WatchExperimentCommand {}
struct WatchDefinitiveRejection: Error { let error: WatchExperimentError }
struct WatchExecutionUncertain: Error {}
struct Coordinator {
    // ACTUAL_HANDLER
}
@main struct Checks {
    static func main() async {
        let coordinator = Coordinator()
        do {
            try await coordinator.executeRecordHandler({ _ in
                throw WatchDefinitiveRejection(error: .phoneBusy)
            }, command: .init())
            fatalError("expected pre-dispatch failure")
        } catch WatchExperimentError.phoneBusy {
            print("PASS: pre-dispatch rejection is definitive")
        } catch { fatalError("unexpected error: \(error)") }
        do {
            try await coordinator.executeRecordHandler({ _ in
                throw WatchExperimentError.phoneBusy
            }, command: .init())
            fatalError("expected uncertain result")
        } catch is WatchExecutionUncertain {
            print("PASS: unproven handler failure remains uncertain")
        } catch { fatalError("unexpected error: \(error)") }
    }
}
