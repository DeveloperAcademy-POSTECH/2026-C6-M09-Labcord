import SwiftUI

public struct TooltipGestureGuide: View {
    private let message: String

    public init(_ message: String = "제스처를 사용해 빠르고 편리하게 기록하는 법을 배워보세요") {
        self.message = message
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(message)
                .typography(Typography.calloutSemiBold)
                .foregroundStyle(Color(.General.Brand.onSubtle))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LayoutTokens.spacing16)
                .padding(.vertical, LayoutTokens.spacing12)
                .background(
                    Color(.General.Fill.light),
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: LayoutTokens.radiusSm,
                        bottomLeadingRadius: LayoutTokens.radiusSm,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: LayoutTokens.radiusSm
                    )
                )

            Image("tooltip-gesture-beak", bundle: .module)
                .renderingMode(.template)
                .foregroundStyle(Color(.General.Fill.light))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: 244)
        .accessibilityElement(children: .combine)
    }
}

#Preview("제스처 안내 툴팁") {
    TooltipGestureGuide()
        .padding()
}
