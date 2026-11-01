import SwiftUI

public struct LiveActivityContainer<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 106)
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
