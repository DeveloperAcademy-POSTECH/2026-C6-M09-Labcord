import SwiftUI

public struct NavigationPageTitle: View {
    private let title: String
    private let onBack: (() -> Void)?

    public init(_ title: String, onBack: (() -> Void)? = nil) {
        self.title = title
        self.onBack = onBack
    }

    public var body: some View {
        HStack(spacing: 0) {
            if let onBack {
                Button(action: onBack) {
                    LabcordIconArtwork(icon: .caretLeft, size: 24)
                        .foregroundStyle(Color(.General.Label.secondary))
                        .frame(width: 50, height: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("뒤로")
            }

            Text(title)
                .typography(Typography.headline)
                .foregroundStyle(Color(.General.Label.primary))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            if onBack != nil {
                Color.clear
                    .frame(width: 50, height: 50)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 50)
        .padding(.horizontal, LayoutTokens.spacing16)
    }
}

#Preview("페이지 제목") {
    VStack {
        NavigationPageTitle("실험 등록") { }
        NavigationPageTitle("실험 등록")
    }
}
