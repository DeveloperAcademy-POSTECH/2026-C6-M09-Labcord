import Foundation

enum WatchSnapshotPublicationPolicy {
    static func orderedIDs(known: Set<UUID>, visible: UUID?) -> [UUID] {
        let remaining = known.filter { $0 != visible }.sorted { $0.uuidString < $1.uuidString }
        guard let visible else { return remaining }
        return remaining + [visible]
    }

    static func isPhoneSessionActive(
        id: UUID, visible: UUID?, sceneActive: Bool, applicationActive: Bool, running: Bool
    ) -> Bool {
        visible == id && sceneActive && applicationActive && running
    }
}
