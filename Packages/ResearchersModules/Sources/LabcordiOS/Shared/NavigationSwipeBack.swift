//
//  NavigationSwipeBack.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 11/3/26.
//

import SwiftUI
import UIKit

private struct NavigationSwipeBack: UIViewControllerRepresentable {
    let enabled: Bool
    
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }
    
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.setEnabled(enabled)
    }
    
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restore()
    }
    
    final class Controller: UIViewController {
        private var shouldEnable = false
        private var isVisible = false
        private weak var gesture: UIGestureRecognizer?
        private weak var previousDelegate: UIGestureRecognizerDelegate?
        private var previousIsEnabled: Bool?
        
        func setEnabled(_ enabled: Bool) {
            shouldEnable = enabled
            if isVisible { apply() }
        }
        
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isVisible = true
            apply()
        }
        
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            isVisible = false
            restore()
        }
        
        private func apply() {
            if gesture == nil {
                var ancestor = parent
                
                while let controller = ancestor {
                    if let navigationController = controller as? UINavigationController,
                       let popGesture = navigationController.interactivePopGestureRecognizer,
                       navigationController.viewControllers.count > 1 {
                        gesture = popGesture
                        previousDelegate = popGesture.delegate
                        previousIsEnabled = popGesture.isEnabled
                        break
                    }
                    ancestor = controller.parent
                }
            }
            
            guard let gesture else { return }
            gesture.delegate = shouldEnable ? nil : previousDelegate
            gesture.isEnabled = shouldEnable
        }
        
        func restore() {
            guard let gesture else { return }
            gesture.delegate = previousDelegate
            if let previousIsEnabled {
                gesture.isEnabled = previousIsEnabled
            }
            self.gesture = nil
            previousDelegate = nil
            previousIsEnabled = nil
        }
    }
}

public extension View {
    func navigationSwipeBackEnabled(_ enabled: Bool) -> some View {
        background {
            NavigationSwipeBack(enabled: enabled)
                .frame(width: 0, height: 0)
        }
    }
}
