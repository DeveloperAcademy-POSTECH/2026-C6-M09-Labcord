import SwiftUI
#if os(iOS)
import UIKit
#endif

public extension View {
    func labcordInputFocus(_ focus: FocusState<Bool>.Binding) -> some View {
        modifier(
            LabcordInputFocusModifier(
                focus: focus,
                focusedValue: true,
                unfocusedValue: false
            )
        )
    }

    func labcordInputFocus<Value: Hashable>(
        _ focus: FocusState<Value?>.Binding,
        equals value: Value
    ) -> some View {
        modifier(
            LabcordInputFocusModifier(
                focus: focus,
                focusedValue: value,
                unfocusedValue: nil
            )
        )
    }

    func labcordDismissKeyboardOnTapOutside() -> some View {
        modifier(LabcordInputDismissalModifier())
    }

    func labcordKeyboardDismissalDisabled(_ disabled: Bool = true) -> some View {
        modifier(LabcordInputDismissExclusionModifier(isExcluded: disabled))
    }
}

private struct LabcordInputFocusModifier<Value: Hashable>: ViewModifier {
    let focus: FocusState<Value>.Binding
    let focusedValue: Value
    let unfocusedValue: Value

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.labcordInputDismissRequest) private var dismissRequest

    func body(content: Content) -> some View {
        content
            .focused(focus, equals: focusedValue)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard isEnabled, focus.wrappedValue != focusedValue else { return }
                    focus.wrappedValue = focusedValue
                }
            )
            .onChange(of: dismissRequest) { _, _ in
                if focus.wrappedValue == focusedValue {
                    focus.wrappedValue = unfocusedValue
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: LabcordInputBoundsPreferenceKey.self,
                            value: isEnabled ? [geometry.frame(in: .global)] : []
                        )
                }
                .allowsHitTesting(false)
            }
    }
}

private struct LabcordInputDismissalModifier: ViewModifier {
    @State private var inputBounds: [CGRect] = []
    @State private var dismissRequest = 0
    @State private var focusedInput: LabcordFocusedInput?
    @State private var viewportBounds = CGRect.zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { scroll in
            content
                .environment(\.labcordInputDismissRequest, dismissRequest)
                .onPreferenceChange(LabcordInputBoundsPreferenceKey.self) { bounds in
                    inputBounds = bounds
                }
                .onPreferenceChange(LabcordFocusedInputPreferenceKey.self) { inputs in
                    let nextInput = inputs.last
                    guard focusedInput != nextInput else { return }
                    let needsReveal = focusedInput?.id != nextInput?.id
                        || focusedInput?.height != nextInput?.height
                    focusedInput = nextInput
                    if needsReveal { revealFocusedInput(using: scroll) }
                }
                .onGeometryChange(for: CGRect.self) { geometry in
                    geometry.frame(in: .global)
                } action: { bounds in
                    let sizeChanged = viewportBounds.size != bounds.size
                    viewportBounds = bounds
                    if sizeChanged { revealFocusedInput(using: scroll) }
                }
                #if os(iOS)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIResponder.keyboardDidShowNotification
                    )
                ) { _ in
                    revealFocusedInput(using: scroll)
                }
                #endif
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                        let isInsideInput = inputBounds.contains { $0.contains(value.location) }
                        guard !isInsideInput else { return }
                        dismissRequest += 1
                    }
                )
        }
    }

    private func revealFocusedInput(using scroll: ScrollViewProxy) {
        guard let focusedInput, !viewportBounds.isEmpty, !focusedInput.frame.isEmpty,
              !viewportBounds.contains(focusedInput.frame) else { return }
        let anchor: UnitPoint = focusedInput.height > viewportBounds.height ? .top : .bottom
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            scroll.scrollTo(focusedInput.id, anchor: anchor)
        }
    }
}

struct LabcordFocusedInput: Equatable, Sendable {
    let id: UUID
    let frame: CGRect

    var height: CGFloat { frame.height }
}

struct LabcordFocusedInputPreferenceKey: PreferenceKey {
    static let defaultValue: [LabcordFocusedInput] = []

    static func reduce(
        value: inout [LabcordFocusedInput], nextValue: () -> [LabcordFocusedInput]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private struct LabcordInputDismissExclusionModifier: ViewModifier {
    let isExcluded: Bool

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: LabcordInputBoundsPreferenceKey.self,
                        value: isExcluded ? [geometry.frame(in: .global)] : []
                    )
            }
            .allowsHitTesting(false)
        }
    }
}

private struct LabcordInputBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private extension EnvironmentValues {
    @Entry var labcordInputDismissRequest = 0
}
