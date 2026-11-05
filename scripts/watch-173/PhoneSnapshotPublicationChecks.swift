import Foundation

@main
enum PhoneSnapshotPublicationChecks {
    static func main() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let fresh = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let ids = WatchSnapshotPublicationPolicy.orderedIDs(known: [first, second], visible: fresh)
        precondition(ids == [first, second, fresh])
        precondition(
            WatchSnapshotPublicationPolicy.orderedIDs(known: [first, second], visible: first)
                == [second, first]
        )
        precondition(
            WatchSnapshotPublicationPolicy.orderedIDs(known: [first, second], visible: nil)
                == [first, second]
        )
        func active(
            id: UUID = first, visible: UUID? = first, scene: Bool = true,
            app: Bool = true, running: Bool = true
        ) -> Bool {
            WatchSnapshotPublicationPolicy.isPhoneSessionActive(
                id: id, visible: visible, sceneActive: scene, applicationActive: app,
                running: running
            )
        }
        precondition(active())
        precondition(!active(visible: nil))
        precondition(!active(visible: second))
        precondition(!active(scene: false))
        precondition(!active(app: false))
        precondition(!active(running: false))
        print("PASS: uncached visible session is published last and only active while running")
    }
}
