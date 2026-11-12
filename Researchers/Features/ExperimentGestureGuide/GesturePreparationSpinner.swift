import LabcordDesignSystem
import SwiftUI
import UIKit

struct GesturePreparationSpinner: UIViewRepresentable {
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = UIColor(Color("Experiment/Label/Brand"))
        indicator.startAnimating()
        return indicator
    }

    func updateUIView(_ indicator: UIActivityIndicatorView, context: Context) {
        if !indicator.isAnimating { indicator.startAnimating() }
    }
}
