//
//  VisualEffectView.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 11/5/26.
//

import SwiftUI
import UIKit

public struct VisualEffectView: UIViewRepresentable {
    private let effect: UIVisualEffect?

    public init(effect: UIVisualEffect?) {
        self.effect = effect
    }

    public func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: effect)
    }

    public func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}

#Preview {
    VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
}
