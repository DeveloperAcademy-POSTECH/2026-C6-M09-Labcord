import LabcordDesignSystem
import SwiftUI

struct ProtocolAnalysisProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringAnimating = false
    let scanCompleted: Bool
    let extractionCompleted: Bool
    let isCancelling: Bool
    var notice: String?
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ProgressRing(value: 0.25, showPercentage: false)
                        .rotationEffect(.degrees(ringAnimating && !reduceMotion ? 360 : 0))
                        .animation(
                            reduceMotion ? nil
                                : .linear(duration: 1.3).repeatForever(autoreverses: false),
                            value: ringAnimating
                        )
                        .onAppear { ringAnimating = true }
                        .accessibilityLabel("프로토콜 분석 중")
                        .accessibilityValue("진행률 확인 중")

                    VStack(spacing: 8) {
                        Text(isCancelling ? "분석을 취소하고 있어요" : "프로토콜 분석 중...")
                            .typography(Typography.title3SemiBold)
                        Text("프로토콜 기반으로 실험 준비 중이에요.")
                            .typography(Typography.subheadline)
                            .foregroundStyle(Color(
                                "General/Label/Secondary",
                                bundle: LabcordDesignSystemResources.bundle
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
                        "General/Label/Secondary", bundle: LabcordDesignSystemResources.bundle
                    ))
                    .multilineTextAlignment(.center)
                Button(action: onCancel) {
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
    }
}

#Preview("프로토콜 분석 중") {
    let fontRegistration = FontRegistration.register()
    ProtocolAnalysisProgressView(
        scanCompleted: false,
        extractionCompleted: false,
        isCancelling: false
    ) {}
    .id(fontRegistration)
}
