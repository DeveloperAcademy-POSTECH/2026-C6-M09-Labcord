import Foundation
import LabcordShared

@MainActor
final class WatchRemoteIntentReceiver {
    static let shared = WatchRemoteIntentReceiver()

    private struct Entry {
        let request: WatchRemoteIntentRequest
        let task: Task<WatchRemoteIntentResponse, Never>
    }

    private var entries: [UUID: Entry] = [:]

    func receive(_ request: WatchRemoteIntentRequest) async -> WatchRemoteIntentResponse {
        let now = Date.now
        entries = entries.filter { $0.value.request.expiresAt > now }
        guard request.expiresAt > now, request.expiresAt.timeIntervalSince(now) <= 15 else {
            return response(request, accepted: false, message: "요청 시간이 만료됐어요.")
        }
        if let existing = entries[request.requestID] {
            guard existing.request == request else {
                return response(request, accepted: false, message: "요청을 확인할 수 없어요.")
            }
            return await existing.task.value
        }
        let task = Task { @MainActor in
            do {
                let message = try await WatchIntentRuntime.shared.performRemoteVoice(
                    experimentID: request.experimentID, expiresAt: request.expiresAt
                )
                return self.response(request, accepted: true, message: message)
            } catch {
                return self.response(request, accepted: false, message: error.localizedDescription)
            }
        }
        entries[request.requestID] = Entry(request: request, task: task)
        return await task.value
    }

    private func response(
        _ request: WatchRemoteIntentRequest, accepted: Bool, message: String
    ) -> WatchRemoteIntentResponse {
        WatchRemoteIntentResponse(
            requestID: request.requestID, accepted: accepted, message: message
        )
    }
}
