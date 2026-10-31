import SwiftUI

public struct TimelineExperimentState: View {
    private let timestamp: String
    private let title: String

    public init(_ title: String, timestamp: String) {
        self.init(timestamp: timestamp, title: title)
    }

    public init(
        timestamp: String = "10:17:24",
        title: String = "실험 시작"
    ) {
        self.timestamp = timestamp
        self.title = title
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutTokens.spacing12) {
            Text(timestamp)
                .typography(Typography.body)
                .foregroundStyle(Color("General/Label/Secondary", bundle: .module))
                .frame(minWidth: 70, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(title)
                .typography(Typography.bodySemiBold)
                .foregroundStyle(Color("General/Label/Primary", bundle: .module))
                .contentTransition(.opacity)
                .labcordMotion(.state, value: title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.vertical, LayoutTokens.spacing8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

public typealias LabcordExperimentStatusTimelineItem = TimelineExperimentState

#Preview("실험 상태 타임라인") {
    _ = FontRegistration.register()
    return VStack(alignment: .leading, spacing: 0) {
        TimelineExperimentState()
        TimelineExperimentState(timestamp: "10:25:09", title: "실험 일시정지")
        TimelineExperimentState(timestamp: "11:02:41", title: "실험 종료")
    }
    .foregroundStyle(Color("General/Label/Primary", bundle: .module))
    .background(Color("General/Background/Primary", bundle: .module))
}

#Preview("실험 상태 타임라인 · 큰 글자") {
    _ = FontRegistration.register()
    return TimelineExperimentState(
        timestamp: "오후 10:17:24",
        title: "실험 상태가 변경되었습니다"
    )
    .frame(maxWidth: .infinity)
    .environment(\.dynamicTypeSize, .accessibility3)
}
