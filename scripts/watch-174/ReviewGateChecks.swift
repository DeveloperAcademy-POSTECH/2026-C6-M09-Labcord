import Foundation

@main
struct ReviewGateChecks {
    @MainActor
    static func main() async throws {
        let gate = WatchAudioReviewGate()
        let id = UUID()
        var completed = false
        let decision = Task { @MainActor in
            let save = await gate.wait(id)
            completed = true
            return save
        }
        await Task.yield()
        try await Task.sleep(for: .milliseconds(3100))
        precondition(gate.contains(id) && !completed, "backend must not auto-save after 3 seconds")
        gate.resolve(id, save: true)
        let save = await decision.value
        precondition(save && completed)
        let cancelled = Task { @MainActor in await gate.wait(UUID()) }
        await Task.yield()
        gate.cancelAll()
        let cancelledResult = await cancelled.value
        precondition(!cancelledResult)
        print("PASS: UI owns countdown; explicit save and cancellation release review gate")
    }
}
