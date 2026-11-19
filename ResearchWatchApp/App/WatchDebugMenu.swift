#if DEBUG
import SwiftUI

struct WatchDebugResetAction {
    var call: (() -> Void)?
}

extension EnvironmentValues {
    @Entry var watchDebugReset = WatchDebugResetAction()
}

struct WatchDebugMenuModifier: ViewModifier {
    @Environment(\.watchDebugReset) private var reset
    @State private var shortcut = WatchDebugShortcut()
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isPresented)
            .simultaneousGesture(
                SpatialEventGesture()
                    .onChanged { shortcut.update($0) }
                    .onEnded { events in
                        if shortcut.finish(events) { isPresented = true }
                    }
            )
            .overlay {
                if isPresented {
                    VStack(spacing: 12) {
                        Text("디버깅 메뉴")
                            .font(.headline)
                        Button("처음으로 초기화", role: .destructive) {
                            isPresented = false
                            reset.call?()
                        }
                        Button("닫기") { isPresented = false }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                }
            }
    }
}

private struct WatchDebugShortcut {
    private typealias Event = SpatialEventCollection.Event

    private var starts: [Event.ID: Event] = [:]
    private var ended: Set<Event.ID> = []
    private var overlapped = false
    private var invalid = false
    private var taps: [TimeInterval] = []

    mutating func update(_ events: SpatialEventCollection) {
        var activeCount = 0
        for event in events where event.kind == .touch {
            switch event.phase {
            case .active:
                activeCount += 1
                if starts[event.id] == nil { starts[event.id] = event }
            case .ended:
                ended.insert(event.id)
            case .cancelled:
                invalid = true
            @unknown default:
                invalid = true
            }
            guard let start = starts[event.id] else { continue }
            let distance = hypot(
                event.location.x - start.location.x, event.location.y - start.location.y
            )
            invalid = invalid || distance > 18
        }
        overlapped = overlapped || activeCount == 2
    }

    mutating func finish(_ events: SpatialEventCollection) -> Bool {
        update(events)
        defer {
            starts.removeAll()
            ended.removeAll()
            overlapped = false
            invalid = false
        }
        guard overlapped, !invalid, starts.count == 2, ended.count == 2,
              let start = starts.values.map(\.timestamp).min(),
              let end = events.map(\.timestamp).max(), end - start <= 0.25 else {
            taps.removeAll()
            return false
        }
        taps.removeAll { end - $0 > 1 }
        taps.append(start)
        guard taps.count == 3 else { return false }
        taps.removeAll()
        return true
    }
}
#endif
