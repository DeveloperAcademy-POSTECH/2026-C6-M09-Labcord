import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    @ViewBuilder
    func labcordSliderPressObservation(_ isPressed: Binding<Bool>) -> some View {
        #if os(iOS)
        background {
            SliderPressObservation(isPressed: isPressed)
                .allowsHitTesting(false)
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct SliderPressObservation: UIViewRepresentable {
    @Binding var isPressed: Bool

    func makeUIView(context: Context) -> SliderPressObservationView {
        SliderPressObservationView(frame: .zero)
    }

    func updateUIView(_ view: SliderPressObservationView, context: Context) {
        view.observationEnabled = context.environment.isEnabled
        view.onPressedChange = { isPressed = $0 }
    }

    static func dismantleUIView(_ view: SliderPressObservationView, coordinator: ()) {
        view.stopObserving()
    }
}

private final class SliderPressObservationView: UIView, UIGestureRecognizerDelegate {
    var observationEnabled = true
    var onPressedChange: ((Bool) -> Void)?
    private weak var observedWindow: UIWindow?
    private let observer = SliderPressObserver(target: nil, action: nil)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.delegate = self
        observer.onPressedChange = { [weak self] pressed in self?.onPressedChange?(pressed) }
    }

    required init?(coder: NSCoder) { return nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard observedWindow !== window else { return }
        stopObserving()
        observedWindow = window
        window?.addGestureRecognizer(observer)
    }

    func stopObserving() {
        let wasPressed = observer.isObservingPress
        let observerCallback = observer.onPressedChange
        observer.onPressedChange = nil
        observedWindow?.removeGestureRecognizer(observer)
        observer.onPressedChange = observerCallback
        observedWindow = nil
        if wasPressed {
            let callback = onPressedChange
            DispatchQueue.main.async { callback?(false) }
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
    ) -> Bool {
        guard observationEnabled, window != nil, !isHidden else { return false }
        var ancestor: UIView? = self
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0 else { return false }
            ancestor = view.superview
        }
        return bounds.contains(touch.location(in: self))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }
}

private final class SliderPressObserver: UIGestureRecognizer {
    var onPressedChange: ((Bool) -> Void)?
    private(set) var isObservingPress = false
    private weak var trackedTouch: UITouch?

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(
        by preventingGestureRecognizer: UIGestureRecognizer
    ) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else { return }
        trackedTouch = touch
        updatePress(true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {}

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        updatePress(false)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        updatePress(false)
        state = .failed
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
        updatePress(false)
    }

    private func updatePress(_ pressed: Bool) {
        guard isObservingPress != pressed else { return }
        isObservingPress = pressed
        onPressedChange?(pressed)
    }
}
#endif
