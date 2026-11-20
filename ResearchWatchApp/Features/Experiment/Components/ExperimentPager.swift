import LabcordDesignSystem
import SwiftUI

struct ExperimentPager<Record: View, Timers: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selection: Int
    @ViewBuilder let record: () -> Record
    @ViewBuilder let timers: () -> Timers
    @GestureState private var drag: PageDrag?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var gestureRevision = 0

    private var activeDrag: PageDrag? {
        guard let drag, drag.page == selection, drag.revision == gestureRevision,
              drag.movesPage else { return nil }
        return drag
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                page(record(), number: 1, size: geometry.size)
                page(timers(), number: 2, size: geometry.size)
            }
            .animation(activeDrag == nil && !reduceMotion ? LabcordMotion.settle.animation : nil) {
                $0.offset(x: -CGFloat(selection - 1) * geometry.size.width + dragOffset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(pageGesture(width: geometry.size.width))
        }
        .coordinateSpace(name: ExperimentPagerCoordinateSpace.viewport)
        .onPreferenceChange(ExperimentPagerRowFrames.self) { rowFrames = $0 }
        .onChange(of: selection) { _, _ in gestureRevision &+= 1 }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { gestureRevision &+= 1 }
        }
        .onDisappear { gestureRevision &+= 1 }
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
        .updating($drag) { value, state, transaction in
            transaction.animation = nil
            if state == nil {
                let startsOnRow = selection == 2
                    && rowFrames.values.contains { $0.contains(value.startLocation) }
                state = PageDrag(
                    page: selection, revision: gestureRevision,
                    movesPage: !startsOnRow
                        && abs(value.translation.width) > abs(value.translation.height)
                )
            }
            state?.translation = value.translation.width
        }
        .onEnded { value in
            guard let drag = activeDrag, width > 0 else { return }
            let distance = value.predictedEndTranslation.width
            guard abs(distance) > width * 0.25 else { return }
            selection = min(2, max(1, drag.page + (distance < 0 ? 1 : -1)))
        }
    }

    private struct PageDrag {
        let page: Int
        let revision: Int
        let movesPage: Bool
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
