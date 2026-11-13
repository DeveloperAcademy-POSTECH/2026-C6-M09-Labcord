import LabcordDesignSystem
import SwiftUI

struct FirstHomeHelpButton: View {
    let isGuideVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(labcordIcon: .questionmark)
        }
        .buttonStyle(.labcordIcon(
            isGuideVisible ? .plain : .neutral,
            size: .large,
            colorPalette: .general
        ))
        .background {
            if isGuideVisible {
                Circle().fill(Color("General/Fill/Light"))
            }
        }
    }
}
