import Foundation
import LabcordShared
import WatchConnectivity

extension WatchConnectivitySession {
    public func resolveGestureRoute(
        _ request: WatchGesturePracticeRequest, until deadline: ContinuousClock.Instant
    ) async throws -> WatchGestureRouteReply.Route? {
        activate()
        guard let session else { return nil }
        let data = try JSONEncoder().encode(request)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let state = WatchConnectivityState(session)
            if state.canTransfer, state.reachable { break }
            let next = ContinuousClock.now.advanced(by: .milliseconds(50))
            try await Task.sleep(until: min(next, deadline), tolerance: .zero, clock: .continuous)
        }
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { return nil }

        let (stream, replies) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let timeout = Task {
            try await Task.sleep(until: deadline, tolerance: .zero, clock: .continuous)
            replies.finish()
        }
        defer {
            timeout.cancel()
            replies.finish()
        }
        let key = WatchGesturePracticeRequest.messageKey
        session.sendMessage([key: data]) { @Sendable reply in
            if let data = reply[key] as? Data, data.count <= 16_384 { replies.yield(data) }
            replies.finish()
        } errorHandler: { @Sendable _ in
            replies.finish()
        }
        var iterator = stream.makeAsyncIterator()
        let reply = await iterator.next()
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline, let reply,
              let decoded = try? JSONDecoder().decode(WatchGestureRouteReply.self, from: reply),
              decoded.requestID == request.requestID else { return nil }
        return decoded.route
    }
}
