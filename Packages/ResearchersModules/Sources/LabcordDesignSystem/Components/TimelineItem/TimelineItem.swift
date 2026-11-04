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
    private let photoAspectRatio: CGFloat
    private let content: AnyView?

    @ScaledMetric(relativeTo: .callout) private var memoMinimumHeight = 42

    public init<Content: View>(
        _ title: String,
        timestamp: String,
        memoTitle: String = "메모",
        memo: String = "",
        showMemo: Bool = false,
        type: TimelineItemType = .voice,
        state: TimelineItemState = .default,
        photoAspectRatio: CGFloat = 16.0 / 9.0,
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
            photoAspectRatio: photoAspectRatio,
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
        photoAspectRatio: CGFloat = 16.0 / 9.0,
        content: AnyView? = nil
    ) {
        self.timestamp = timestamp
        self.title = title
        self.memoTitle = memoTitle
        self.memo = memo
        self.showMemo = showMemo
        self.type = type
        self.state = state
        self.photoAspectRatio = photoAspectRatio
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
        photoAspectRatio: CGFloat = 16.0 / 9.0,
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
            photoAspectRatio: photoAspectRatio,
            content: AnyView(content())
        )
    }

    public var body: some View {
        HStack(alignment: .top, spacing: LayoutTokens.spacing4) {
            Text(timestamp)
                .typography(Typography.body)
                .foregroundStyle(Color(.General.Label.tertiary))
                .frame(minWidth: 70, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: contentSpacing) {
                if type == .voice {
                    Text(title)
                        .typography(Typography.bodySemiBold)
                        .foregroundStyle(Color(.General.Label.primary))
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
            .padding(12)
            .background(Color(.General.Background.Grouped.primary))
            .cornerRadius(LayoutTokens.radiusSm)
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.vertical, LayoutTokens.spacing8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: state == .selected ? LayoutTokens.radiusSm : 0))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var recordContent: some View {
        switch type {
        case .voice:
            content ?? AnyView(VoicePlayer())
        case .photo:
            if let content {
                GeometryReader { geometry in
                    content
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height,
                            alignment: .center
                        )
                        .clipped()
                }
                .aspectRatio(photoAspectRatio, contentMode: .fit)
                .cornerRadius(LayoutTokens.radiusSm)
            }
        case .video:
            if let content {
                content
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .overlay {
                        Button {} label: {
                            Image(labcordIcon: .play)
                                .foregroundStyle(Color(.General.Label.light))
                        }
                        .background(Color(.General.Fill.secondary))
                        .cornerRadius(LayoutTokens.radiusFull)
                        .buttonStyle(.labcordIcon(.neutral, size: .large))
                    }
                    .cornerRadius(LayoutTokens.radiusSm)
            }
        case .timer:
            content ?? AnyView(TimerRecord())
        }
    }

    private var contentSpacing: CGFloat {
        type == .voice ? LayoutTokens.spacing8 : LayoutTokens.spacing12
    }

    private var memoContent: some View {
        Text(memo)
            .typography(Typography.callout)
            .foregroundStyle(Color(.General.Label.secondary))
            .contentTransition(.opacity)
            .labcordMotion(.state, value: memo)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
            .fill(Color(.General.Fill.primary))
            .opacity(state == .selected ? 1 : 0)
            .labcordMotion(.state, value: state.rawValue)
            .allowsHitTesting(false)
    }
}

#Preview("타임라인 · 미디어") {
    _ = FontRegistration.register()
    return ScrollView {
        VStack(spacing: 0) {
            TimelineItem(type: .voice)
            TimelineItem(showMemo: false, type: .voice, state: .selected)
            TimelineItem(
                title: "사진 기록",
                type: .photo,
                state: .default,
                photoAspectRatio: 3.0 / 4.0
            ) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.General.Fill.secondary))
                    .overlay {
                        Text("호출자 미디어 슬롯")
                            .typography(Typography.callout)
                            .foregroundStyle(Color(.General.Label.secondary))
                    }
            }
        }
    }
    .foregroundStyle(Color(.General.Label.primary))
    .background(Color(.General.Background.primary))
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
