import Foundation
import WatchConnectivity

@MainActor
public final class WatchRecordTransport {
    public static let snapshotKey = "record.snapshot.v1"
    private static let maximumPayloadBytes = 200_000
    private var latest: [UUID: WatchRecordSnapshot] = [:]
    private var observers: [UUID: AsyncStream<WatchRecordSnapshot>.Continuation] = [:]
    public private(set) var lastPublishError: WatchExperimentError?

    public init() {}

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
            records.forEach { accept($0) }
        } else if let record = try? JSONDecoder().decode(WatchRecordSnapshot.self, from: data) {
            accept(record)
        }
    }

    public func publish(_ record: WatchRecordSnapshot, session: WCSession?) {
        let changed = accept(record)
        guard changed || latest[record.id] == record else { return }
        resend(session: session)
        if let session, session.activationState == .activated,
           record.phase == .saved || record.phase == .cancelled {
            transfer(record, session: session)
        }
    }

    public func resend(session: WCSession?) {
        guard let session, session.activationState == .activated else {
            lastPublishError = .notReachable
            return
        }
        let records = latest.values.sorted { $0.id.uuidString < $1.id.uuidString }
        do {
            let data = try JSONEncoder().encode(records)
            guard data.count <= Self.maximumPayloadBytes else {
                throw WatchExperimentError.resultUnknown
            }
            var context = session.applicationContext
            context[Self.snapshotKey] = data
            try session.updateApplicationContext(context)
            lastPublishError = nil
        } catch {
            lastPublishError = .resultUnknown
            for record in records { transfer(record, session: session) }
        }
    }

    private func transfer(_ record: WatchRecordSnapshot, session: WCSession) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(record)
            guard data.count <= Self.maximumPayloadBytes else {
                lastPublishError = .resultUnknown
                return
            }
            guard !session.outstandingUserInfoTransfers.contains(where: {
                ($0.userInfo[Self.snapshotKey] as? Data) == data
            }) else { return }
            session.transferUserInfo([Self.snapshotKey: data])
        } catch {
            lastPublishError = .resultUnknown
        }
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
