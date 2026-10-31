import SwiftUI

public struct ExperimentTitleSection<Leading: View, Trailing: View>: View {
    public enum Layout: String, CaseIterable, Sendable {
        case horizontal
        case vertical
    }

    private let title: String
    private let layout: Layout
    private let leading: Leading
    private let trailing: Trailing
    private let tokens = LayoutTokens()

    public init(
        title: String,
        layout: Layout,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.layout = layout
        self.leading = leading()
        self.trailing = trailing()
    }

    @ViewBuilder
    public var body: some View {
        switch layout {
        case .horizontal:
            horizontalContent
        case .vertical:
            verticalContent
        }
    }

    private var horizontalContent: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: tokens.spacing16) {
                leading
                titleView
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(.leading, 62)
        .padding(.trailing, 70)
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    private var verticalContent: some View {
        HStack(alignment: .center, spacing: tokens.spacing16) {
            leading
            titleView
        }
        .padding(.horizontal, tokens.spacing16)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    }

    private var titleView: some View {
        Text(title)
            .typography(Typography.headline)
            .foregroundStyle(Color("General/Label/Secondary", bundle: .module))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }
}

public extension ExperimentTitleSection where Trailing == EmptyView {
    init(
        title: String,
        layout: Layout,
        @ViewBuilder leading: () -> Leading
    ) {
        self.init(
            title: title,
            layout: layout,
            leading: leading,
            trailing: EmptyView.init
        )
    }
}

#Preview("Horizontal") {
    _ = FontRegistration.register()
    return ExperimentTitleSection(
        title: "촉매 반응 조건 비교 실험 A",
        layout: .horizontal,
        leading: {
            Button("타이머", action: noTitleSectionAction)
        },
        trailing: {
            HStack(spacing: 24) {
                Button("음성", action: noTitleSectionAction)
                Button("사진", action: noTitleSectionAction)
                Button("영상", action: noTitleSectionAction)
            }
        }
    )
    .frame(width: 749)
    .padding()
    .background(Color("General/Background/Primary", bundle: .module))

}

#Preview("Vertical · 긴 제목") {
    _ = FontRegistration.register()
    return ExperimentTitleSection(
        title: "아주 긴 실험 제목도 접근성 글자 크기에서 잘리지 않습니다",
        layout: .vertical
    ) {
        Button("타이머", action: noTitleSectionAction)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
    .frame(width: 401)
    .padding()
    .background(Color("General/Background/Primary", bundle: .module))

}

private func noTitleSectionAction() { }
