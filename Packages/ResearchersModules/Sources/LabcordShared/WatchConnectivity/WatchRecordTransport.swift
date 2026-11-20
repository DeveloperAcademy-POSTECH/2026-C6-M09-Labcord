import Foundation
import WatchConnectivity

@MainActor
public final class WatchRecordTransport {
    public nonisolated static let snapshotKey = "record.snapshot.v1"
    private static let maximumPayloadBytes = 200_000
    private var latest: [UUID: WatchRecordSnapshot] = [:]
    private var observers: [UUID: AsyncStream<WatchRecordSnapshot>.Continuation] = [:]
    private var activeExperimentID: UUID?
    private var needsContextUpdate = false
    private var liveRecords: [UUID: [UUID: WatchRecordSnapshot]] = [:]
    private var recentResults: [UUID: [WatchRecordSnapshot.Kind: WatchRecordSnapshot]] = [:]
    private var pendingResults: [UUID: WatchRecordSnapshot] = [:]
    public private(set) var lastPublishError: WatchExperimentError?
    public var acceptsRemoteEpoch: ((WatchStateEpoch?) -> Bool)?

    public init() {}

    public func clearSnapshots() {
        latest.removeAll()
        activeExperimentID = nil
        needsContextUpdate = true
        liveRecords.removeAll()
        recentResults.removeAll()
        pendingResults.removeAll()
        lastPublishError = nil
    }

    public func stream() -> AsyncStream<WatchRecordSnapshot> {
        let id = UUID()
        let bufferCount = max(64, latest.count)
        return AsyncStream(bufferingPolicy: .bufferingNewest(bufferCount)) { continuation in
            observers[id] = continuation
            latest.values.forEach { continuation.yield($0) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.observers.removeValue(forKey: id) }
            }
        }
    }

    public func receive(_ data: Data) {
        guard data.count <= Self.maximumPayloadBytes else { return }
        if let records = try? JSONDecoder().decode([WatchRecordSnapshot].self, from: data) {
            records.forEach { receive($0) }
        } else if let record = try? JSONDecoder().decode(WatchRecordSnapshot.self, from: data) {
            receive(record)
        }
    }

    public func receive(_ record: WatchRecordSnapshot) {
        guard record.experimentID != nil, record.revision != nil,
              acceptsRemoteEpoch?(record.epoch) ?? true else { return }
        accept(record)
    }

    public func publish(_ record: WatchRecordSnapshot, session: WCSession?) {
        guard accept(record), let experimentID = record.experimentID else { return }
        pendingResults.removeValue(forKey: record.id)
        if record.phase == .saved || record.phase == .cancelled
            || (record.phase == .failed && record.originalRetained == false) {
            liveRecords[experimentID]?.removeValue(forKey: record.id)
            recentResults[experimentID, default: [:]][record.kind] = record
            #if !targetEnvironment(simulator)
            if record.phase != .failed, !transfer(record, session: session) {
                pendingResults[record.id] = record
            }
            #endif
        } else {
            liveRecords[experimentID, default: [:]][record.id] = record
        }
        if activeExperimentID == experimentID { publishActiveContext(session: session) }
    }

    public func restoreResult(_ record: WatchRecordSnapshot) {
        guard let experimentID = record.experimentID else { return }
        if let previous = recentResults[experimentID]?[record.kind] {
            guard let date = record.startedAt, let previousDate = previous.startedAt,
                  previousDate < date else { return }
        }
        recentResults[experimentID, default: [:]][record.kind] = record
        if activeExperimentID == experimentID { needsContextUpdate = true }
    }

    public func resend(experimentID: UUID?, session: WCSession?, force: Bool = false) {
        let changed = activeExperimentID != experimentID
        activeExperimentID = experimentID
        if changed || force || needsContextUpdate {
            publishActiveContext(session: session, force: force)
        }
        guard force else { return }
        for record in Array(pendingResults.values) where transfer(record, session: session) {
            pendingResults.removeValue(forKey: record.id)
        }
    }

    public func retryOnRecovery(_ data: Data) {
        guard let record = try? JSONDecoder().decode(WatchRecordSnapshot.self, from: data),
              record.phase == .saved || record.phase == .cancelled,
              latest[record.id] == record else { return }
        pendingResults[record.id] = record
    }

    private func publishActiveContext(session: WCSession?, force: Bool = false) {
        guard let session, WatchConnectivityState(session).canTransfer else {
            lastPublishError = .notReachable
            return
        }
        needsContextUpdate = false
        let records: [WatchRecordSnapshot] = activeExperimentID.map { id in
            var selected = liveRecords[id] ?? [:]
            for record in (recentResults[id] ?? [:]).values {
                selected[record.id] = selected[record.id] ?? record
            }
            return selected.values.sorted { $0.id.uuidString < $1.id.uuidString }
        } ?? []
        do {
            let data = try sortedEncoder().encode(records)
            guard data.count <= Self.maximumPayloadBytes else {
                throw WatchExperimentError.resultUnknown
            }
            try WatchConnectivityDiagnostics.updateContext(
                session, key: Self.snapshotKey, data: data, force: force
            )
            lastPublishError = nil
        } catch {
            lastPublishError = .resultUnknown
            for record in records { _ = transfer(record, session: session) }
        }
    }

    private func transfer(_ record: WatchRecordSnapshot, session: WCSession?) -> Bool {
        do {
            let data = try sortedEncoder().encode(record)
            guard data.count <= Self.maximumPayloadBytes else {
                lastPublishError = .resultUnknown
                return false
            }
            return WatchConnectivityDiagnostics.queueUserInfo(
                [Self.snapshotKey: data], on: session
            )
        } catch {
            lastPublishError = .resultUnknown
            return false
        }
    }

    private func sortedEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    @discardableResult
    private func accept(_ record: WatchRecordSnapshot) -> Bool {
        guard let experimentID = record.experimentID, let revision = record.revision else {
            return false
        }
        if let previous = latest[record.id] {
            guard previous.experimentID == experimentID,
                  revision > (previous.revision ?? 0) else { return false }
        }
        latest[record.id] = record
        observers.values.forEach { $0.yield(record) }
        return true
    }
}
