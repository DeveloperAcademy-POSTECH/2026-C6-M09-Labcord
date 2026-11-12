import LabcordDesignSystem
import SwiftUI

struct FirstHomeHelpButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(labcordIcon: .questionmark)
        }
        .buttonStyle(.labcordIcon(.neutral, size: .large, isLoading: false))
    }
}
