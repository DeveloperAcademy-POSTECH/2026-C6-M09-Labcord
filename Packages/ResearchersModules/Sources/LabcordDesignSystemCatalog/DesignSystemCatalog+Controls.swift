import LabcordDesignSystem
import SwiftUI

struct DesignSystemControlsPage: View {
    let item: CatalogItem

    @State private var selectedChipIDs: Set<Int> = [1]
    @State private var chipItems = catalogChipItems
    @State private var nextChipID = (catalogChipItems.map(\.id).max() ?? 0) + 1

    var body: some View {
        DesignSystemCatalogPage(title: item.title, context: item.context) {
            switch item {
            case .button:
                DesignSystemCatalogCard(
                    "Button · iOS", description: "크기·스타일·상태·역할을 선택하고 실제 동작 확인"
                ) {
                    CatalogControlButtonScenario(iconOnly: false)
                }
            case .iconButton:
                DesignSystemCatalogCard(
                    "Icon Button · iOS", description: "아이콘과 90개 크기·외형·상태·역할 조합"
                ) {
                    CatalogControlButtonScenario(iconOnly: true)
                }
            case .icons:
                DesignSystemCatalogCard(
                    "Icon Library",
                    description: "전체 아이콘을 크기와 이름으로 확인"
                ) {
                    CatalogIconGridLayout {
                        ForEach(LabcordIcon.allCases) { icon in
                            VStack(spacing: 6) {
                                Image(labcordIcon: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .frame(minWidth: 32, minHeight: 32)

                                Text(icon.rawValue)
                                    .typography(Typography.caption2)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text(icon.rawValue))
                        }
                    }
                }
            case .dropdownTrigger:
                DesignSystemCatalogCard(
                    "Dropdown Trigger", description: "메뉴를 열어 상태를 선택하는 드롭다운"
                ) {
                    CatalogControlDropdownScenario()
                }
            case .checkbox:
                DesignSystemCatalogCard("Checkbox", description: "체크박스의 크기와 선택 상태") {
                    CatalogCheckboxScenario()
                }
            case .radioButton:
                DesignSystemCatalogCard("Radio Button", description: "같은 선택값을 공유하는 라디오 버튼") {
                    CatalogRadioButtonScenario()
                }
            case .chip:
                DesignSystemCatalogCard(
                    "Chip", description: "선택, 아이콘, 닫기 동작을 확인하는 칩"
                ) {
                    CatalogControlChipScenario()
                }
            case .chipGroup:
                DesignSystemCatalogCard(
                    "Chip Group",
                    description: "항목을 선택하고 추가·제거하는 칩 목록"
                ) {
                    LabcordChipGroup(
                        chipItems,
                        selection: $selectedChipIDs,
                        label: \.title,
                        onRemove: { item in
                            chipItems.removeAll { $0.id == item.id }
                        },
                        onAdd: {
                            let item = CatalogChipItem(
                                id: nextChipID, title: "샘플 \(nextChipID)"
                            )
                            nextChipID += 1
                            chipItems.append(item)
                            selectedChipIDs.insert(item.id)
                        }
                    )
                }
            case .textField:
                DesignSystemCatalogCard(
                    "Text Field", description: "이름을 입력하고 안내 문구를 확인하는 필드"
                ) {
                    CatalogControlInputScenario(isMultiline: false)
                }
            case .textArea:
                DesignSystemCatalogCard(
                    "Text Area", description: "여러 줄 메모를 입력하는 영역"
                ) {
                    CatalogControlInputScenario(isMultiline: true)
                }
            case .statusBadge:
                DesignSystemCatalogCard("Status Badge") {
                    CatalogControlStatusBadgeScenario()
                }
            case .separator:
                DesignSystemCatalogCard("Separator") {
                    CatalogControlSeparatorScenario()
                }
            case .overlay:
                DesignSystemCatalogCard("Overlay") {
                    CatalogControlOverlayScenario()
                }
            case .loadingIndicator:
                loadingIndicatorCard
            default:
                EmptyView()
            }
        }
    }
}

private extension DesignSystemControlsPage {
    var loadingIndicatorCard: some View {
        DesignSystemCatalogCard(
            "Loading Indicator",
            description: "크기를 선택하고 반복 움직임 확인"
        ) {
            CatalogControlLoadingScenario()
        }
    }

}

private struct CatalogIconGridLayout: Layout {
    private let minimumColumnWidth: CGFloat = 72
    private let columnSpacing: CGFloat = 12
    private let rowSpacing: CGFloat = 16

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        measurement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let measured = measurement(width: bounds.width, subviews: subviews)
        var rowY = bounds.minY
        for (row, height) in measured.rowHeights.enumerated() {
            for column in 0..<measured.columns {
                let index = row * measured.columns + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(
                        x: bounds.minX + CGFloat(column) * (measured.columnWidth + columnSpacing)
                            + measured.columnWidth / 2,
                        y: rowY + height / 2
                    ),
                    anchor: .center,
                    proposal: ProposedViewSize(width: measured.columnWidth, height: nil)
                )
            }
            rowY += height + rowSpacing
        }
    }

    private func measurement(width proposedWidth: CGFloat?, subviews: Subviews) -> Measurement {
        let width = proposedWidth.flatMap { $0.isFinite ? max(minimumColumnWidth, $0) : nil }
            ?? minimumColumnWidth
        let columns = max(1,
                          Int((width + columnSpacing) / (minimumColumnWidth + columnSpacing)))
        let columnWidth = (width - CGFloat(columns - 1) * columnSpacing) / CGFloat(columns)
        let rowCount = (subviews.count + columns - 1) / columns
        var heights = Array(repeating: CGFloat.zero, count: rowCount)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            )
            heights[index / columns] = max(heights[index / columns], size.height)
        }
        let height = heights.reduce(0, +) + CGFloat(max(0, rowCount - 1)) * rowSpacing
        return Measurement(
            size: CGSize(width: width, height: height),
            columns: columns, columnWidth: columnWidth, rowHeights: heights
        )
    }

    private struct Measurement {
        let size: CGSize
        let columns: Int
        let columnWidth: CGFloat
        let rowHeights: [CGFloat]
    }
}

#Preview("공통 컨트롤 카탈로그") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemControlsPage(item: .button)
    }
}
