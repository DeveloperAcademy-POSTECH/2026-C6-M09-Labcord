import Foundation
import LabcordShared
import WatchConnectivity

extension WatchConnectivitySession {
    public func experimentLists() -> AsyncStream<WatchExperimentListUpdate> {
        activate()
        if let context = session?.receivedApplicationContext {
            receiveList(
                context[WatchExperimentTransport.listSnapshotKey] as? Data,
                versionData: context[WatchExperimentTransport.listVersionKey] as? Data
            )
        }
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            listObservers[id] = continuation
            if let latestList {
                continuation.yield(.snapshot(latestList))
            } else if let epoch = experiments.remoteEpoch {
                continuation.yield(.invalidated(epoch))
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.listObservers.removeValue(forKey: id) }
            }
        }
    }

    public func loadExperiments() async throws -> WatchExperimentList {
        try await waitForActivation()
        guard let session else { throw WatchExperimentError.notReachable }
        let command = WatchExperimentCommand(operation: .list)
        let response: WatchExperimentResponse
        if session.isReachable {
            do {
                response = try await experiments.send(command, session: session)
            } catch {
                try Task.checkCancellation()
                response = try await backgroundResponse(for: command, session: session)
            }
        } else {
            response = try await backgroundResponse(for: command, session: session)
        }
        guard response.version == WatchExperimentCommand.schemaVersion,
              response.phase == .completed, let summaries = response.experiments else {
            throw response.error ?? .invalidPayload
        }
        if let screen = response.screen { experiments.receiveScreen(screen) }
        acceptList(summaries, version: response.listVersion)
        guard let latestList else { throw WatchExperimentError.staleRevision }
        return latestList
    }

    func receiveList(_ data: Data?, versionData: Data?) {
        guard let data,
              let summaries = try? JSONDecoder().decode([WatchExperimentSummary].self, from: data)
        else { return }
        let version = versionData.flatMap {
            try? JSONDecoder().decode(WatchStateVersion.self, from: $0)
        }
        guard versionData == nil || version != nil else { return }
        acceptList(summaries, version: version)
    }

    private func acceptList(_ summaries: [WatchExperimentSummary], version: WatchStateVersion?) {
        guard experiments.acceptEpoch(version?.epoch) else { return }
        if let previous = latestList?.version {
            guard let version, version.isNewer(than: previous) else { return }
        }
        let list = WatchExperimentList(
            experiments: summaries.filter { $0.status != .completed }, version: version
        )
        guard latestList != list else { return }
        latestList = list
        listObservers.values.forEach { $0.yield(.snapshot(list)) }
    }
}

private extension WatchConnectivitySession {
    func backgroundResponse(
        for command: WatchExperimentCommand,
        session: WCSession
    ) async throws -> WatchExperimentResponse {
        let (responses, continuation) = backgroundResponses(for: command)
        let timeout = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled { continuation?.yield(nil) }
        }
        defer {
            timeout.cancel()
            continuation?.finish()
        }
        let data = try JSONEncoder().encode(command)
        let key = WatchExperimentTransport.backgroundCommandKey
        _ = try? WatchConnectivityDiagnostics.updateContext(session, key: key, data: data)
        transferUserInfo([key: data])
        var iterator = responses.makeAsyncIterator()
        let received = await withTaskCancellationHandler {
            await iterator.next()
        } onCancel: {
            continuation?.yield(nil)
        }
        guard let result = received, let response = result else {
            try Task.checkCancellation()
            throw WatchExperimentError.deliveryTimeout
        }
        return response
    }

    func backgroundResponses(
        for command: WatchExperimentCommand
    ) -> (
        AsyncStream<WatchExperimentResponse?>,
        AsyncStream<WatchExperimentResponse?>.Continuation?
    ) {
        let key = WatchExperimentTransport.backgroundResponseKey
        var responseContinuation: AsyncStream<WatchExperimentResponse?>.Continuation?
        let responses = AsyncStream<WatchExperimentResponse?> { continuation in
            responseContinuation = continuation
            let observerID = addUserInfoObserver { userInfo in
                if let data = userInfo[key] as? Data,
                   let value = try? JSONDecoder().decode(
                       WatchExperimentResponse.self, from: data
                   ), value.requestID == command.requestID {
                    continuation.yield(value)
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.removeUserInfoObserver(observerID) }
            }
        }
        return (responses, responseContinuation)
    }
}
