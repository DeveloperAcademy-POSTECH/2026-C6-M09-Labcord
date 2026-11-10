import ComposableArchitecture
import Foundation
import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

struct RemoteExperimentPreparation: View {
    let store: StoreOf<ExperimentSessionFeature>

    var body: some View {
        VStack(spacing: 20) {
            Text(store.detail?.title ?? "실험")
                .typography(Typography.title3)
            if store.sharedStage == .countdown, let end = store.sharedCountdownEndsAt {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    Text("\(max(0, Int(ceil(end.timeIntervalSince(context.date)))))")
                        .font(.largeTitle.monospacedDigit())
                }
                Text("Watch에서 실험을 시작하고 있어요.")
            } else {
                Text(message)
                if store.sharedStage == .timers {
                    SessionTimerView(
                        store: store.scope(state: \.timer, action: \.timer), isPortrait: true
                    )
                    .allowsHitTesting(false)
                    .frame(height: 280)
                }
                Button(startTitle) {
                    store.send(.beginRemotePreview)
                }
                .buttonStyle(.labcord(.primary, size: .large))
            }
            Button("홈으로") {
                store.send(.cancelRemotePreview)
            }
            .buttonStyle(.labcord(.secondary, size: .large))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(.black)
    }

    private var message: String {
        switch store.sharedStage {
        case .permission: "Watch에서 마이크 권한을 확인하고 있어요."
        case .resumeConfirmation: "실험을 계속할까요?"
        case .paused, .timers: "실험이 일시정지되어 있어요."
        default: "Watch에서 선택한 실험이에요."
        }
    }

    private var startTitle: String {
        switch store.sharedStage {
        case .paused, .timers, .resumeConfirmation: "실험 계속하기"
        default: "실험 시작"
        }
    }
}

struct PauseOverlay: ViewModifier {
    let store: StoreOf<ExperimentSessionFeature>

    func body(content: Content) -> some View {
        content.overlay {
            if store.isPausePresented {
                ExperimentPauseView(
                    store: store.scope(state: \.pause, action: \.pause),
                    timerStore: store.scope(state: \.timer, action: \.timer),
                    canCloseSession: store.canCloseSession
                )
            }
        }
    }
}
