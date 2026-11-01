import SwiftUI

public struct SlideToEndButton: View {
    @Binding private var isTriggered: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var scaledLabelWidth: CGFloat = 110
    @ScaledMetric(relativeTo: .subheadline) private var scaledHeight: CGFloat = 50
    @GestureState private var dragDistance: CGFloat = 0

    public init(isTriggered: Binding<Bool>, action: @escaping () -> Void) {
        _isTriggered = isTriggered
        self.action = action
    }

    public var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let thumbWidth = min(height, availableWidth)
            let travel = max(availableWidth - thumbWidth - 2, 0)
            let progress = isTriggered ? 1 : (travel > 0 ? min(dragDistance / travel, 1) : 0)

            HStack(spacing: 8) {
                IconArtwork(icon: .stop, size: 24)
                    .foregroundStyle(Color(.General.Action.Destructive.foreground))
                    .frame(width: thumbWidth, height: height)
                    .background(Color(.General.Action.Destructive.background), in: Circle())

                if progress == 0 {
                    Text("밀어서 실험 종료")
                        .typography(Typography.subheadline)
                        .foregroundStyle(Color(.General.Label.secondary))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .frame(
                            width: max(availableWidth - thumbWidth - 10, 0),
                            alignment: .leading
                        )
                }
            }
            .padding(.horizontal, 1)
            .frame(
                width: availableWidth - (travel * progress),
                height: height,
                alignment: .leading
            )
            .background(Color(.General.Feedback.Error.subtle), in: Capsule())
            .frame(width: availableWidth, height: height, alignment: .trailing)
            .contentShape(Capsule())
            .gesture(dragGesture(travel: travel))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isTriggered)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("실험 종료")
            .accessibilityValue(isTriggered ? "종료 요청됨" : "대기 중")
            .accessibilityHint("오른쪽으로 밀어 실험을 종료합니다.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { trigger() }
        }
        .frame(maxWidth: preferredWidth)
        .frame(height: height)
    }

    private var height: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? max(scaledHeight, 50) : 50
    }

    private var preferredWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? height + scaledLabelWidth + 10 : 170
    }

    private func dragGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragDistance) { value, state, _ in
                guard isEnabled, !isTriggered else { return }
                state = max(value.translation.width, 0)
            }
            .onEnded { value in
                guard travel > 0, value.translation.width >= travel else { return }
                trigger()
            }
    }

    private func trigger() {
        guard isEnabled, !isTriggered else { return }
        isTriggered = true
        action()
    }
}

#Preview("밀어서 실험 종료") {
    @Previewable @State var isTriggered = false
    SlideToEndButton(isTriggered: $isTriggered) { }
        .padding()
}
