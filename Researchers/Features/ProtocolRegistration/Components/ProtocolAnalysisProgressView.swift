import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct ProtocolAnalysisProgressView: View {
    @Bindable var store: StoreOf<ProtocolAnalysisProgressFeature>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: Double
    let scanCompleted: Bool
    let extractionCompleted: Bool
    let isCancelling: Bool
    var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ProgressRing(value: progress)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: progress)
                        .accessibilityLabel("프로토콜 분석 진행률")

                    VStack(spacing: 8) {
                        Text(isCancelling ? "분석을 취소하고 있어요" : "프로토콜 분석 중...")
                            .typography(Typography.title3SemiBold)
                        Text("프로토콜 기반으로 실험 준비 중이에요.")
                            .typography(Typography.subheadline)
                            .foregroundStyle(Color(
                                "General/Label/Secondary"
                            ))
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 48)

                    VStack(spacing: 11) {
                        StatusPill("프로토콜 스캔 중...", appearance: .general,
                                   showIcon: scanCompleted)
                        StatusPill("타이머 및 용어 추출 중...", appearance: .general,
                                   showIcon: extractionCompleted)
                        StatusPill("맞춤형 실험 준비 중...", appearance: .general, showIcon: false)
                    }
                    .padding(.top, 48)

                    if let notice {
                        Text(notice)
                            .typography(Typography.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            VStack(spacing: 12) {
                Text("분석을 건너뛰고, 실험을 시작할 수 있어요.")
                    .typography(Typography.subheadline)
                    .foregroundStyle(Color(
                        "General/Label/Secondary"
                    ))
                    .multilineTextAlignment(.center)
                Button { store.send(.skipTapped) } label: {
                    Text(isCancelling ? "취소 중..." : "분석 건너뛰기")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.labcord(.secondary, size: .large))
                .disabled(isCancelling)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .accessibilityIdentifier("protocol-analysis-progress")
        .alert("프로토콜 분석을 건너뛸까요?", isPresented: Binding(
            get: { store.showSkipConfirmation },
            set: { if !$0 { store.send(.dismissSkipConfirmation) } }
        )) {
            Button("분석 건너뛰기", role: .destructive) { store.send(.confirmSkip) }
            Button("취소", role: .cancel) { store.send(.dismissSkipConfirmation) }
        } message: {
            Text("분석을 건너뛰면 분석 결과없이 실험을 진행해요.")
        }
        .alert("프로토콜 분석을 종료할까요?", isPresented: Binding(
            get: { store.showExitConfirmation },
            set: { if !$0 { store.send(.dismissExitConfirmation) } }
        )) {
            Button("분석 종료", role: .destructive) { store.send(.confirmExit) }
            Button("취소", role: .cancel) { store.send(.dismissExitConfirmation) }
        } message: {
            Text("분석을 종료하면 분석 결과가 초기화 돼요.")
        }
    }
}

#Preview("프로토콜 분석 중") {
    let fontRegistration = FontRegistration.register()
    ProtocolAnalysisProgressView(
        store: Store(initialState: ProtocolAnalysisProgressFeature.State()) {
            ProtocolAnalysisProgressFeature()
        },
        progress: 0.5,
        scanCompleted: false,
        extractionCompleted: false,
        isCancelling: false
    )
    .id(fontRegistration)
}
