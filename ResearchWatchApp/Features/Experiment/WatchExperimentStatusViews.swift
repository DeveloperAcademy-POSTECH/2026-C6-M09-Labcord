import SwiftUI

struct WatchPreparationView: View {
    let value: String

    var body: some View {
        Image("WatchPreparationRing")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 149)
            .overlay {
                Text(value)
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .accessibilityLabel(value == "준비" ? "실험 준비" : "실험 시작까지 \(value)초")
    }
}
