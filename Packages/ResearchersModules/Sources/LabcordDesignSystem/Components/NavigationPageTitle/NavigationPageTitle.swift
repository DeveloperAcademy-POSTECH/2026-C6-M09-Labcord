import SwiftUI

public struct NavigationPageTitle: View {
    public enum Appearance: Sendable {
        case general, experiment
    }

    private let title: String
    private let foregroundColor: Color?
    private let onBack: (() -> Void)?
    private let appearance: Appearance
    private let showsTitle: Bool

    public init(
        _ title: String,
        appearance: Appearance = .general,
        foregroundColor: Color? = nil,
        showsTitle: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        self.title = title
        self.foregroundColor = foregroundColor
        self.onBack = onBack
        self.appearance = appearance
        self.showsTitle = showsTitle
    }

    public var body: some View {
        HStack(spacing: 0) {
            if let onBack {
                Button(action: onBack) {
                    IconArtwork(icon: .caretLeft, size: 24)
                        .foregroundStyle(iconColor)
                        .frame(width: 50, height: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("뒤로")
            }

            Group {
                if showsTitle {
                    Text(title)
                        .typography(Typography.headline)
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.center)
                }
            }
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

    private var titleColor: Color {
        foregroundColor ?? Color(
            appearance == .general
                ? .General.Label.primary : .Experiment.Label.primary
        )
    }

    private var iconColor: Color {
        foregroundColor ?? Color(
            appearance == .general
                ? .General.Label.secondary : .Experiment.Label.secondary
        )
    }
}

#Preview("페이지 제목") {
    VStack {
        NavigationPageTitle("실험 등록") { }
        NavigationPageTitle("실험 등록")
        NavigationPageTitle("실험 기록", foregroundColor: .white) { }
            .background(.black)
    }
}

#Preview("실험 화면 페이지 제목") {
    NavigationPageTitle("실험", appearance: .experiment) { }
        .background(Color(.Experiment.Background.primary))
}
