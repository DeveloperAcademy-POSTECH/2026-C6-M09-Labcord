import SwiftUI

public enum TimelineItemType: String, CaseIterable, Sendable {
    case voice
    case photo
    case video
    case timer
}

public enum TimelineItemState: String, CaseIterable, Sendable {
    case `default`
    case selected
}

public struct TimelineItem: View {
    private let timestamp: String
    private let title: String
    private let memoTitle: String
    private let memo: String
    private let showMemo: Bool
    private let type: TimelineItemType
    private let state: TimelineItemState
    private let content: AnyView?

    private let tokenLayout = LayoutTokens()
    @ScaledMetric(relativeTo: .callout) private var memoMinimumHeight = 42

    public init<Content: View>(
        _ title: String,
        timestamp: String,
        memoTitle: String = "메모",
        memo: String = "",
        showMemo: Bool = false,
        type: TimelineItemType = .voice,
        state: TimelineItemState = .default,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            timestamp: timestamp,
            title: title,
            memoTitle: memoTitle,
            memo: memo,
            showMemo: showMemo,
            type: type,
            state: state,
            content: content
        )
    }

    public init(
        timestamp: String = "10:17:24",
        title: String = "샘플 B, 반응 시작 5분 후 연한 노란색으로 변했고 침전은 없음",
        memoTitle: String = "메모",
        memo: String = "색이 연한 노란색으로 변했으나 침전은 없음",
        showMemo: Bool = true,
        type: TimelineItemType = .voice,
        state: TimelineItemState = .default,
        content: AnyView? = nil
    ) {
        self.timestamp = timestamp
        self.title = title
        self.memoTitle = memoTitle
        self.memo = memo
        self.showMemo = showMemo
        self.type = type
        self.state = state
        self.content = content
    }

    public init<Content: View>(
        timestamp: String = "10:17:24",
        title: String = "샘플 B, 반응 시작 5분 후 연한 노란색으로 변했고 침전은 없음",
        memoTitle: String = "메모",
        memo: String = "색이 연한 노란색으로 변했으나 침전은 없음",
        showMemo: Bool = true,
        type: TimelineItemType = .voice,
        state: TimelineItemState = .default,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            timestamp: timestamp,
            title: title,
            memoTitle: memoTitle,
            memo: memo,
            showMemo: showMemo,
            type: type,
            state: state,
            content: AnyView(content())
        )
    }

    public var body: some View {
        HStack(alignment: .top, spacing: tokenLayout.spacing12) {
            Text(timestamp)
                .typography(Typography.body)
                .foregroundStyle(Color("General/Label/Secondary", bundle: .module))
                .frame(minWidth: 70, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: contentSpacing) {
                if type == .voice {
                    Text(title)
                        .typography(Typography.bodySemiBold)
                        .foregroundStyle(Color("General/Label/Primary", bundle: .module))
                        .contentTransition(.opacity)
                        .labcordMotion(.state, value: title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                recordContent

                if showMemo {
                    memoContent
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .labcordMotion(.layout, value: showMemo)
        }
        .padding(.horizontal, tokenLayout.spacing16)
        .padding(.vertical, tokenLayout.spacing8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: state == .selected ? tokenLayout.radiusSm : 0))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var recordContent: some View {
        switch type {
        case .voice:
            content ?? AnyView(VoicePlayer())
        case .photo, .video:
            if let content {
                content
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
        case .timer:
            content ?? AnyView(TimerRecord())
        }
    }

    private var contentSpacing: CGFloat {
        type == .voice ? tokenLayout.spacing8 : tokenLayout.spacing12
    }

    private var memoContent: some View {
        VStack(alignment: .leading, spacing: tokenLayout.spacing12) {
            Text(memoTitle)
                .typography(Typography.calloutSemiBold)
                .foregroundStyle(Color("General/Label/Tertiary", bundle: .module))
                .fixedSize(horizontal: false, vertical: true)

            Text(memo)
                .typography(Typography.callout)
                .foregroundStyle(Color("General/Label/Primary", bundle: .module))
                .contentTransition(.opacity)
                .labcordMotion(.state, value: memo)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: memoMinimumHeight, alignment: .topLeading)
        }
        .padding(tokenLayout.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color("General/Timeline/Memo/Background", bundle: .module),
            in: RoundedRectangle(cornerRadius: tokenLayout.radiusSm)
        )
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: tokenLayout.radiusSm)
            .fill(Color("General/Fill/Primary", bundle: .module))
            .opacity(state == .selected ? 1 : 0)
            .labcordMotion(.state, value: state.rawValue)
            .allowsHitTesting(false)
    }
}

public typealias LabcordTimelineItem = TimelineItem

#Preview("타임라인 · 미디어") {
    _ = FontRegistration.register()
    return ScrollView {
        VStack(spacing: 0) {
            TimelineItem(type: .voice)
            TimelineItem(showMemo: false, type: .voice, state: .selected)
            TimelineItem(
                title: "사진 기록",
                type: .photo,
                state: .default
            ) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("General/Fill/Secondary", bundle: .module))
                    .frame(height: 160)
                    .overlay {
                        Text("호출자 미디어 슬롯")
                            .typography(Typography.callout)
                            .foregroundStyle(Color("General/Label/Secondary", bundle: .module))
                    }
            }
        }
    }
    .foregroundStyle(Color("General/Label/Primary", bundle: .module))
    .background(Color("General/Background/Primary", bundle: .module))
}

#Preview("타임라인 · 큰 글자") {
    _ = FontRegistration.register()
    return TimelineItem(
        timestamp: "오후 10:17:24",
        title: "긴 한국어 기록 제목도 잘리지 않고 다음 줄로 확장됩니다.",
        memo: "긴 메모는 Dynamic Type 환경에서 여러 줄로 확장됩니다.",
        type: .timer,
        state: .selected
    )
    .frame(maxWidth: .infinity)
    .environment(\.dynamicTypeSize, .accessibility3)
}
