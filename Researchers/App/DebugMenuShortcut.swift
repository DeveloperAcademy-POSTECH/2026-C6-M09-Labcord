import ComposableArchitecture
import SwiftUI
import UIKit

struct DebugMenuShortcut: UIViewRepresentable {
    let store: StoreOf<AppFeature>
    let isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> WindowAnchor {
        let anchor = WindowAnchor()
        anchor.isUserInteractionEnabled = false
        anchor.windowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return anchor
    }

    func updateUIView(_ view: WindowAnchor, context: Context) {
        context.coordinator.setPresented(isPresented)
    }

    static func dismantleUIView(_ view: WindowAnchor, coordinator: Coordinator) {
        coordinator.attach(to: nil)
    }

    final class WindowAnchor: UIView {
        var windowChanged: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowChanged?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate,
        UIAdaptivePresentationControllerDelegate {
        private let store: StoreOf<AppFeature>
        private weak var window: UIWindow?
        private weak var menu: UIViewController?
        private var isPresented = false
        private var tapTimes: [TimeInterval] = []

        private lazy var recognizer: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(registerTap))
            tap.numberOfTouchesRequired = 3
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            return tap
        }()

        init(store: StoreOf<AppFeature>) {
            self.store = store
        }

        func attach(to window: UIWindow?) {
            guard self.window !== window else { return }
            self.window?.removeGestureRecognizer(recognizer)
            self.window = window
            tapTimes.removeAll()
            window?.addGestureRecognizer(recognizer)
        }

        func setPresented(_ isPresented: Bool) {
            guard self.isPresented != isPresented else { return }
            self.isPresented = isPresented
            Task { @MainActor [weak self] in self?.updatePresentation() }
        }

        private func updatePresentation() {
            if !isPresented {
                menu?.dismiss(animated: true)
                menu = nil
                return
            }

            guard menu == nil, var presenter = window?.rootViewController else { return }
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            let controller = UIHostingController(rootView: DebugMenuView(store: store))
            controller.modalPresentationStyle = .pageSheet
            controller.presentationController?.delegate = self
            menu = controller
            presenter.present(controller, animated: true)
        }

        func presentationControllerShouldDismiss(
            _ presentationController: UIPresentationController
        ) -> Bool {
            !store.debugMenu.isWorking
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            menu = nil
            store.send(.debugMenu(.close))
        }

        @objc private func registerTap() {
            guard !store.debugMenu.isPresented else { return }
            let now = ProcessInfo.processInfo.systemUptime
            tapTimes.removeAll { now - $0 > 1 }
            tapTimes.append(now)
            guard tapTimes.count == 3 else { return }
            tapTimes.removeAll()
            store.send(.debugMenu(.open))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
