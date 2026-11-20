import SwiftUI

struct ExperimentPager<Record: View, Timers: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selection: Int
    @ViewBuilder let record: () -> Record
    @ViewBuilder let timers: () -> Timers
    @GestureState private var gestureID: UUID?
    @State private var drag: PageDrag?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var gestureRevision = 0

    private var activeDrag: PageDrag? {
        guard let drag, drag.page == selection, drag.revision == gestureRevision,
              drag.movesPage, drag.isTracking else { return nil }
        return drag
    }

    private var settleAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.36)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                page(record(), number: 1, size: geometry.size)
                page(timers(), number: 2, size: geometry.size)
            }
            .animation(activeDrag == nil ? settleAnimation : nil) {
                $0.offset(x: -CGFloat(selection - 1) * geometry.size.width + dragOffset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(pageGesture(width: geometry.size.width))
        }
        .coordinateSpace(name: ExperimentPagerCoordinateSpace.viewport)
        .onPreferenceChange(ExperimentPagerRowFrames.self) { rowFrames = $0 }
        .onChange(of: gestureID) { previous, current in
            guard current == nil, let previous else { return }
            Task { @MainActor in
                await Task.yield()
                guard gestureID == nil, drag?.id == previous else { return }
                withAnimation(settleAnimation) { drag?.isTracking = false }
            }
        }
        .onChange(of: selection) { _, _ in invalidateDrag() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { invalidateDrag() }
        }
        .onDisappear { invalidateDrag() }
    }

    private var dragOffset: CGFloat {
        guard let drag = activeDrag else { return 0 }
        let isBeyondEdge = drag.page == 1 && drag.translation > 0
            || drag.page == 2 && drag.translation < 0
        return isBeyondEdge ? drag.translation * 0.18 : drag.translation
    }

    private func page<Content: View>(
        _ content: Content, number: Int, size: CGSize
    ) -> some View {
        content
            .frame(width: size.width, height: size.height)
            .environment(\.isExperimentPageActive, selection == number)
            .scrollDisabled(selection != number)
            .allowsHitTesting(selection == number)
            .accessibilityHidden(selection != number)
    }

    private func pageGesture(width: CGFloat) -> some Gesture {
        DragGesture(
            minimumDistance: 12,
            coordinateSpace: .named(ExperimentPagerCoordinateSpace.viewport)
        )
        .updating($gestureID) { _, identifier, transaction in
            transaction.animation = nil
            if identifier == nil { identifier = UUID() }
        }
        .onChanged { value in
            guard let gestureID else { return }
            if drag?.id != gestureID {
                let startsOnRow = selection == 2
                    && rowFrames.values.contains { $0.contains(value.startLocation) }
                drag = PageDrag(
                    id: gestureID, page: selection, revision: gestureRevision,
                    movesPage: !startsOnRow
                        && abs(value.translation.width) > abs(value.translation.height)
                )
            }
            drag?.translation = value.translation.width
        }
        .onEnded { value in
            settlePage(distance: value.predictedEndTranslation.width, width: width)
        }
    }

    private func settlePage(distance: CGFloat, width: CGFloat) {
        var target = selection
        if let drag, drag.page == selection, drag.revision == gestureRevision,
           drag.movesPage, width > 0, abs(distance) > width * 0.25 {
            target = min(2, max(1, drag.page + (distance < 0 ? 1 : -1)))
        }
        withAnimation(settleAnimation) {
            selection = target
            drag = nil
        }
    }

    private func invalidateDrag() {
        gestureRevision &+= 1
        if gestureID == nil { drag = nil }
    }

    private struct PageDrag {
        let id: UUID
        let page: Int
        let revision: Int
        let movesPage: Bool
        var isTracking = true
        var translation: CGFloat = 0
    }
}

enum ExperimentPagerCoordinateSpace: Hashable {
    case viewport
}

struct ExperimentPagerRowFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, next in next }
    }
}

private struct IsExperimentPageActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isExperimentPageActive: Bool {
        get { self[IsExperimentPageActiveKey.self] }
        set { self[IsExperimentPageActiveKey.self] = newValue }
    }
}
