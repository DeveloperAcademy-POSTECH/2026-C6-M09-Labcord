import SwiftUI

public struct TimerTabs: View {
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
    private let leftTitle: String
    private let rightTitle: String
    private let layout = LayoutTokens()

    public init(
        selection: Binding<Selection>,
        count: String? = nil,
        showCount: Bool = true,
        style: Style = .plain,
        leftTitle: String = "세팅된 타이머",
        rightTitle: String = "진행중인 타이머"
    ) {
        _selection = selection
        self.count = count
        self.showCount = showCount
        self.style = style
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
    }

    public init(
        selection: Binding<Selection>,
        count: Int?,
        showCount: Bool = true,
        style: Style = .plain,
        leftTitle: String = "세팅된 타이머",
        rightTitle: String = "진행중인 타이머"
    ) {
        self.init(
            selection: selection,
            count: count.map(String.init),
            showCount: showCount,
            style: style,
            leftTitle: leftTitle,
            rightTitle: rightTitle
        )
    }

    public var body: some View {
        HStack(alignment: .center, spacing: layout.spacing12) {
            TimerTabItem(
                title: leftTitle,
                isSelected: selection == .set,
                style: style
            ) {
                selection = .set
            }

            HStack(alignment: .center, spacing: layout.spacing4) {
                TimerTabItem(
                    title: rightTitle,
                    isSelected: selection == .running,
                    style: style
                ) {
                    selection = .running
                }

                Group {
                    if style == .plain, showCount, let count {
                        Text(count)
                            .typography(Typography.callout)
                            .monospacedDigit()
                            .foregroundStyle(Color("Experiment/Label/Brand", bundle: .module))
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
        .padding(style == .pill ? layout.spacing4 : 0)
        .frame(minHeight: style == .plain ? 54 : nil)
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
        .background(Color("Experiment/Background/Primary", bundle: .module))
}

#Preview("선택 상태") {
    @Previewable @State var selection = TimerTabs.Selection.running

    _ = FontRegistration.register()
    return TimerTabs(selection: $selection, count: 3)
        .padding()
        .background(Color("Experiment/Background/Primary", bundle: .module))
}
