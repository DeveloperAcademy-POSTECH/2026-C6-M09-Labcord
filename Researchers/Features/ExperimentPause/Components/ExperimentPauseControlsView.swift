import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct ExperimentPauseControlsView: View {
    let store: StoreOf<ExperimentPauseFeature>
    let canCloseSession: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.send(.resumeTapped)
            } label: {
                Image(labcordIcon: .play)
                    .foregroundStyle(Color("Experiment/Label/Primary"))
            }
            .buttonStyle(.labcordIcon(.neutral, size: .large))
            .background(
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            )
            .cornerRadius(LayoutTokens.radiusFull)

            Button {
                store.send(.returnHomeTapped)
            } label: {
                Text("홈으로 이동")
                    .foregroundStyle(Color("Experiment/Label/Primary"))
            }
            .buttonStyle(.labcord(.plain, size: .medium))
            .disabled(!canCloseSession)

            Spacer()

            SlideToEndButton(
                isTriggered: Binding(
                    get: { store.isEndTriggered },
                    set: { store.send(.endTriggerChanged($0)) }
                )
            ) {
                store.send(.stopTapped)
            }
            .disabled(!canCloseSession)
        }
    }
}
