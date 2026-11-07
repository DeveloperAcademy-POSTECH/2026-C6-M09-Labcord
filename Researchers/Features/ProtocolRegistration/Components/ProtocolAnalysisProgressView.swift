import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct ProtocolAnalysisProgressView: View {
    let phase: ProtocolAnalysisPhase
    let inputName: String?
    let inputNumber: Int?
    let inputCount: Int
    let startedAt: Date?
    let isCancelling: Bool
    var notice: String?
    let onCancel: () -> Void

    private var statusText: String {
        if isCancelling { return "분석 취소 중..." }
        switch phase {
        case .queued: return "시스템에서 분석 시작을 기다리고 있어요"
        case .reading: return "프로토콜을 읽고 있어요"
        case let .readingDocument(phase):
            switch phase {
            case .identifying: return "파일 형식을 확인하고 있어요"
            case .extracting: return "문서에서 본문을 읽고 있어요"
            case .recognizingText: return "사진과 스캔 문자의 글자를 읽고 있어요"
            case .completed, .failed: return "문서 처리 결과를 확인하고 있어요"
            case .cancelled: return "분석 취소 중..."
            }
        case let .terms(progress):
            switch progress {
            case .preparingExtraction: return "용어 추출을 준비하고 있어요"
            case .extractingCandidates: return "본문에서 용어 후보를 찾고 있어요"
            case .preparingRanking: return "용어 검토를 준비하고 있어요"
            case let .rankingCandidates(count):
                return "용어 후보 \(count.formatted())개를 검토하고 있어요"
            case let .rankingProgress(completed, total):
                return "용어 문맥을 검토하고 있어요 · \(completed)/\(total)개 확인"
            case let .classifyingTerms(completed, total):
                return "추출한 용어를 분류하고 있어요 · \(completed)/\(total)개 확인"
            case .organizingTerms: return "용어 분류 결과를 정리하고 있어요"
            }

        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ProgressView()
                        .progressViewStyle(.labcord(
                            size: .large,
                            foreground: Color(
                                "General/Label/Brand", bundle: LabcordDesignSystemResources.bundle
                            )
                        ))
                        .scaleEffect(2)
                        .frame(width: 160, height: 160)
                        .accessibilityLabel("프로토콜 분석 중")

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
                    .padding(.top, 32)

                    Text(statusText)
                        .typography(Typography.calloutSemiBold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(
                            "General/Fill/Primary", bundle: LabcordDesignSystemResources.bundle
                        ), in: Capsule())
                        .padding(.top, 48)

                    if let notice {
                        Text(notice)
                            .typography(Typography.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }
                    if let inputName {
                        VStack(spacing: 4) {
                            if let inputNumber {
                                Text("문서 \(inputNumber)/\(inputCount)")
                                    .typography(Typography.subheadline)
                            }
                            Text(inputName)
                                .typography(Typography.subheadline)
                                .lineLimit(2)
                        }
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                    }
                    if let startedAt {
                        TimelineView(.periodic(from: startedAt, by: 1)) { context in
                            let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
                            Text(String(format: "경과 시간 %d:%02d", seconds / 60, seconds % 60))
                                .typography(Typography.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 32)
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
    let _ = FontRegistration.register()
    ProtocolAnalysisProgressView(
        phase: .reading,
        inputName: "실험 프로토콜.pdf",
        inputNumber: 1,
        inputCount: 1,
        startedAt: nil,
        isCancelling: false,
        onCancel: {}
    )
}
