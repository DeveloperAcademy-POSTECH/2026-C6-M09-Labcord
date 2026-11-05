//
//  VisualEffectView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/5/26.
//

import SwiftUI
import UIKit

struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: effect)
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}

#Preview {
    VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
}
