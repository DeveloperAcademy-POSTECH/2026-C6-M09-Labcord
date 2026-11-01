import SwiftUI

package enum LabcordMotion: Sendable {
    case press
    case release
    case state
    case layout
    case entrance
    case settle

    package var animation: Animation {
        switch self {
        case .press: .spring(response: 0.18, dampingFraction: 0.9)
        case .release: .spring(response: 0.34, dampingFraction: 0.68)
        case .state: .spring(response: 0.28, dampingFraction: 0.82)
        case .layout: .spring(response: 0.36, dampingFraction: 0.84)
        case .entrance: .spring(response: 0.4, dampingFraction: 0.86)
        case .settle: .spring(response: 0.36, dampingFraction: 1)
        }
    }
}

extension View {
    package func labcordMotion<Value: Equatable>(
        _ motion: LabcordMotion = .state,
        value: Value
    ) -> some View {
        modifier(LabcordMotionModifier(motion: motion, value: value))
    }

    func labcordPressFeedback(_ isPressed: Bool, isSubtle: Bool = false) -> some View {
        modifier(LabcordPressModifier(isPressed: isPressed, isSubtle: isSubtle))
    }

    package func labcordEntrance() -> some View {
        modifier(LabcordEntranceModifier())
    }
}

package struct LabcordPlainButtonStyle: ButtonStyle {
    package init() {}

    package func makeBody(configuration: Configuration) -> some View {
        configuration.label.labcordPressFeedback(configuration.isPressed, isSubtle: true)
    }
}

private struct LabcordMotionModifier<Value: Equatable>: ViewModifier {
    let motion: LabcordMotion
    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : motion.animation, value: value)
    }
}

private struct LabcordPressModifier: ViewModifier {
    let isPressed: Bool
    let isSubtle: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { isPressed && isEnabled }
    private var pressedScale: CGFloat { isSubtle ? 0.99 : 0.97 }
    private var pressedOpacity: Double { isSubtle ? 0.94 : 0.86 }

    private var releaseAnimation: Animation {
        isSubtle ? .easeOut(duration: 0.16) : LabcordMotion.release.animation
    }

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion || isActive ? nil : releaseAnimation) {
                $0
                    .scaleEffect(isActive && !reduceMotion ? pressedScale : 1)
                    .opacity(isActive ? pressedOpacity : 1)
            }
    }
}

private struct LabcordEntranceModifier: ViewModifier {
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVisible: Bool { hasAppeared || reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0.88)
            .offset(y: isVisible ? 0 : 4)
            .labcordMotion(.entrance, value: hasAppeared)
            .onAppear { hasAppeared = true }
    }
}
