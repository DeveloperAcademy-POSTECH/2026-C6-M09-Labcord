import SwiftUI

public struct TimerTabs: View {
    public enum Appearance: Sendable {
        case general
        case experiment
    }

    public enum Selection: String, CaseIterable, Sendable {
        case set
        case running
    }

    public enum Style: String, CaseIterable, Sendable {
        case plain
        case pill
    }

    @Binding private var selection: Selection
    private let count: String?
    private let showCount: Bool
    private let style: Style
    private let appearance: Appearance
    private let leftTitle: String
    private let rightTitle: String

    public init(
        selection: Binding<Selection>,
        count: String? = nil,
        showCount: Bool = true,
        style: Style = .plain,
        appearance: Appearance = .experiment,
        leftTitle: String = "세팅된 타이머",
        rightTitle: String = "진행중인 타이머"
    ) {
        _selection = selection
        self.count = count
        self.showCount = showCount
        self.style = style
        self.appearance = appearance
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
    }

    public init(
        selection: Binding<Selection>,
        count: Int?,
        showCount: Bool = true,
        style: Style = .plain,
        appearance: Appearance = .experiment,
        leftTitle: String = "세팅된 타이머",
        rightTitle: String = "진행중인 타이머"
    ) {
        self.init(
            selection: selection,
            count: count.map(String.init),
            showCount: showCount,
            style: style,
            appearance: appearance,
            leftTitle: leftTitle,
            rightTitle: rightTitle
        )
    }

    private var countColor: Color {
        switch appearance {
        case .general: Color(.General.Label.brand)
        case .experiment: Color(.Experiment.Label.brand)
        }
    }

    public var body: some View {
        HStack(alignment: .center, spacing: LayoutTokens.spacing8) {
            TimerTabItem(
                title: leftTitle,
                isSelected: selection == .set,
                style: style,
                appearance: appearance
            ) {
                selection = .set
            }

            HStack(alignment: .center, spacing: LayoutTokens.spacing4) {
                TimerTabItem(
                    title: rightTitle,
                    isSelected: selection == .running,
                    style: style,
                    appearance: appearance
                ) {
                    selection = .running
                }

                Group {
                    if style == .plain, showCount, let count {
                        Text(count)
                            .typography(Typography.callout)
                            .monospacedDigit()
                            .foregroundStyle(countColor)
                            .contentTransition(.opacity)
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityLabel(Text("\(count)개"))
                            .transition(.opacity)
                    }
                }
                .labcordMotion(.state, value: count)
                .labcordMotion(.state, value: showCount)
            }
        }
        .padding(style == .pill ? LayoutTokens.spacing4 : 0)
        .padding(.horizontal, style == .plain ? LayoutTokens.spacing4 : 0)
        .frame(minHeight: style == .plain ? 46 : nil)
        .labcordMotion(.layout, value: style)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("타이머 탭"))
    }
}

#Preview("기본") {
    @Previewable @State var selection = TimerTabs.Selection.set

    _ = FontRegistration.register()
    return TimerTabs(selection: $selection, count: "3")
        .padding()
        .background(Color(.Experiment.Background.primary))
}

#Preview("선택 상태") {
    @Previewable @State var selection = TimerTabs.Selection.running

    _ = FontRegistration.register()
    return TimerTabs(selection: $selection, count: 3)
        .padding()
        .background(Color(.Experiment.Background.primary))
}
