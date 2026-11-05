import Foundation
import LabcordShared

@MainActor
final class WatchIntentRuntime {
    static let shared = WatchIntentRuntime()
    var calls: [(UUID, Date)] = []
    var shouldFail = false
    var waitNanoseconds: UInt64 = 0

    func performRemoteVoice(experimentID: UUID, expiresAt: Date) async throws -> String {
        calls.append((experimentID, expiresAt))
        if waitNanoseconds > 0 { try await Task.sleep(nanoseconds: waitNanoseconds) }
        if shouldFail { throw Failure.denied }
        return "voice accepted"
    }

    enum Failure: LocalizedError {
        case denied
        var errorDescription: String? { "microphone denied" }
    }
}

@main
struct RemoteIntentChecks {
    @MainActor
    static func main() async throws {
        let receiver = WatchRemoteIntentReceiver()
        let runtime = WatchIntentRuntime.shared
        let experiment = UUID()
        let request = WatchRemoteIntentRequest(
            requestID: UUID(), experimentID: experiment, expiresAt: Date().addingTimeInterval(8)
        )
        let encoder = JSONEncoder()
        let decoded = try JSONDecoder().decode(
            WatchRemoteIntentRequest.self, from: encoder.encode(request)
        )
        precondition(decoded == request, "request serialization changed")
        runtime.waitNanoseconds = 20_000_000
        async let first = receiver.receive(request)
        async let second = receiver.receive(request)
        let (firstResult, secondResult) = await (first, second)
        precondition(firstResult == secondResult && firstResult.accepted
            && firstResult.requestID == request.requestID)
        precondition(firstResult.message == "voice accepted" && runtime.calls.count == 1)
        precondition(runtime.calls[0].0 == experiment && runtime.calls[0].1 == request.expiresAt)
        let response = try JSONDecoder().decode(
            WatchRemoteIntentResponse.self, from: encoder.encode(firstResult)
        )
        precondition(response == firstResult, "response serialization changed")
        print("PASS: concurrent duplicate request performs once and returns the same result")
        try await checkOtherCases(receiver: receiver, runtime: runtime, request: request)
    }

    @MainActor
    static func checkOtherCases(
        receiver: WatchRemoteIntentReceiver, runtime: WatchIntentRuntime,
        request: WatchRemoteIntentRequest
    ) async throws {
        let experiment = request.experimentID
        let changed = WatchRemoteIntentRequest(
            requestID: request.requestID, experimentID: UUID(), expiresAt: request.expiresAt
        )
        let conflict = await receiver.receive(changed)
        precondition(!conflict.accepted && runtime.calls.count == 1)
        print("PASS: same request ID with a different experiment is rejected")
        let expired = WatchRemoteIntentRequest(
            requestID: UUID(), experimentID: experiment, expiresAt: Date().addingTimeInterval(-1)
        )
        let expiredResult = await receiver.receive(expired)
        precondition(!expiredResult.accepted && runtime.calls.count == 1)
        let tooLong = WatchRemoteIntentRequest(
            requestID: UUID(), experimentID: experiment, expiresAt: Date().addingTimeInterval(30)
        )
        let longResult = await receiver.receive(tooLong)
        precondition(!longResult.accepted && runtime.calls.count == 1)
        print("PASS: expired and excessive TTL requests never execute")
        runtime.waitNanoseconds = 0
        runtime.shouldFail = true
        let failureRequest = WatchRemoteIntentRequest(
            requestID: UUID(), experimentID: experiment, expiresAt: Date().addingTimeInterval(8)
        )
        let failure = await receiver.receive(failureRequest)
        precondition(!failure.accepted && failure.message == "microphone denied")
        let failureAgain = await receiver.receive(failureRequest)
        precondition(failureAgain == failure && runtime.calls.count == 2)
        print("PASS: runtime failure is propagated and duplicate failure is not replayed")
        runtime.shouldFail = false
        let different = WatchRemoteIntentRequest(
            requestID: UUID(), experimentID: experiment, expiresAt: Date().addingTimeInterval(8)
        )
        let success = await receiver.receive(different)
        precondition(success.accepted && runtime.calls.count == 3)
        print("PASS: a different request ID executes independently")
    }
}
