import SwiftUI

public struct PageControl: View {
    @Binding private var selection: Int
    private let pageCount: Int

    @State private var pressedPage: Int?

    public init(
        pageCount: Int,
        selection: Binding<Int>
    ) {
        self.pageCount = pageCount
        _selection = selection
    }

    public init<Pages: RandomAccessCollection>(
        pages: Pages,
        selection: Binding<Pages.Element>
    ) where Pages.Element: Hashable {
        let values = Array(pages)
        self.init(
            pageCount: values.count,
            selection: Binding<Int>(
                get: {
                    values.firstIndex(of: selection.wrappedValue).map { $0 + 1 } ?? 0
                },
                set: { page, transaction in
                    guard page > 0, values.indices.contains(page - 1) else { return }
                    selection.transaction(transaction).wrappedValue = values[page - 1]
                }
            ).transaction(selection.transaction)
        )
    }

    public var body: some View {
        ZStack {
            HStack(spacing: LayoutTokens.spacing8) {
                if pageCount > 0 {
                    ForEach(1...pageCount, id: \.self) { page in
                        Circle()
                            .fill(
                                page == selection
                                    ? Color(.Experiment.Label.primary)
                                    : Color(.Experiment.Label.quaternary)
                            )
                            .frame(width: dotDiameter(for: page), height: dotDiameter(for: page))
                            .labcordPressFeedback(pressedPage == page, isSubtle: true)
                    }
                }
            }
            .labcordMotion(.state, value: selection)
            .accessibilityHidden(true)

            HStack(spacing: 0) {
                if pageCount > 0 {
                    ForEach(0..<pageCount, id: \.self) { index in
                        pageButton(index: index)
                            .frame(width: interiorHitWidth(index: index))
                    }
                }
            }
        }
        .frame(height: visualHeight)
        .labcordMotion(.layout, value: visualHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("페이지"))
        .accessibilityValue(accessibilityValue)
    }

    private var visualHeight: CGFloat {
        switch pageCount {
        case 2: 30
        case 3: selection == 2 || selection == 3 ? 30 : 32
        default: 34
        }
    }

    private func dotDiameter(for page: Int) -> CGFloat {
        page == selection ? 8 : 6
    }

    private var accessibilityValue: Text {
        guard pageCount > 0, (1...pageCount).contains(selection) else {
            return Text("선택 없음")
        }
        return Text("\(selection) / \(pageCount)")
    }

    private func interiorHitWidth(index: Int) -> CGFloat? {
        index > 0 && index < pageCount - 1 ? 6 + LayoutTokens.spacing8 : nil
    }

    private func pageButton(index: Int) -> some View {
        let page = index + 1
        let isSelected = selection == page

        return Button {
            guard (1...pageCount).contains(page) else { return }
            selection = page
        } label: {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PageControlPressStyle(page: page, pressedPage: $pressedPage))
        .accessibilityLabel(Text("페이지 \(page)"))
        .accessibilityValue(Text(isSelected ? "선택됨" : "선택 안 됨"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PageControlPressStyle: ButtonStyle {
    let page: Int
    @Binding var pressedPage: Int?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    pressedPage = page
                } else if pressedPage == page {
                    pressedPage = nil
                }
            }
            .onDisappear {
                if pressedPage == page { pressedPage = nil }
            }
    }
}

#Preview("두 페이지") {
    @Previewable @State var selection = 1

    _ = FontRegistration.register()
    return PageControl(pageCount: 2, selection: $selection)
        .frame(width: 297)
        .background(Color(.Experiment.Background.primary))
}

#Preview("세 페이지 · 큰 글자") {
    @Previewable @State var selection = 3

    _ = FontRegistration.register()
    return PageControl(pageCount: 3, selection: $selection)
        .frame(width: 297)
        .environment(\.dynamicTypeSize, .accessibility3)
        .background(Color(.Experiment.Background.primary))
}
