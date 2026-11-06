import SwiftUI

public struct LiveActivityContainer<Content: View>: View {
    private let content: Content
    private let minimumContentHeight: CGFloat
    private let maximumContentHeight: CGFloat?

    public init(
        minimumContentHeight: CGFloat = 106,
        maximumContentHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumContentHeight = minimumContentHeight
        self.maximumContentHeight = maximumContentHeight
        self.content = content()
    }

    public var body: some View {
        content
            .frame(
                maxWidth: .infinity,
                minHeight: minimumContentHeight,
                maxHeight: maximumContentHeight
            )
            .padding(.top, 16)
            .padding(.bottom, 16)
            .padding(.leading, 32)
            .padding(.trailing, 24)
            .background(
                Color(.General.Fill.liveActivity),
                in: RoundedRectangle(cornerRadius: 44, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
    }
}

#Preview("Live Activity Container") {
    LiveActivityContainer {
        Text("기록 중")
            .foregroundStyle(.white)
    }
    .padding()
}
