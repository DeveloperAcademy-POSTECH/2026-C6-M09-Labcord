import SwiftUI

public struct ChipGroup<Item: Identifiable>: View where Item.ID: Hashable {
    private let items: [Item]
    @Binding private var selection: Set<Item.ID>
    private let label: (Item) -> String
    private let onRemove: (Item) -> Void
    private let onAdd: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ items: [Item],
        selection: Binding<Set<Item.ID>> = .constant([]),
        label: @escaping (Item) -> String,
        onRemove: @escaping (Item) -> Void,
        onAdd: (() -> Void)? = nil
    ) {
        self.init(
            items: items,
            selection: selection,
            label: label,
            onRemove: onRemove,
            onAdd: onAdd
        )
    }

    public init(
        items: [Item],
        selection: Binding<Set<Item.ID>> = .constant([]),
        label: @escaping (Item) -> String,
        onRemove: @escaping (Item) -> Void = { _ in },
        onAdd: (() -> Void)? = nil
    ) {
        self.items = items
        _selection = selection
        self.label = label
        self.onRemove = onRemove
        self.onAdd = onAdd
    }

    public var body: some View {
        LabcordChipFlowLayout(spacing: LayoutTokens().spacing12) {
            ForEach(items) { item in
                LabcordSetupSmallChip(label: label(item)) {
                    withAnimation(layoutAnimation) {
                        selection.remove(item.id)
                        onRemove(item)
                    }
                }
                .transition(chipTransition)
            }

            if let onAdd {
                Button {
                    withAnimation(layoutAnimation, onAdd)
                } label: {
                    HStack(spacing: LayoutTokens().spacing4) {
                        LabcordIconArtwork(icon: .plus, size: 16, relativeTo: .subheadline)
                        Text("추가")
                            .foregroundStyle(Color("General/Label/Secondary", bundle: .module))
                    }
                }
                .buttonStyle(.labcord(.secondary, size: .small))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(layoutAnimation, value: items.map(\.id))
    }

    private var layoutAnimation: Animation? {
        reduceMotion ? nil : LabcordMotion.layout.animation
    }

    private var chipTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .scale(scale: 0.92, anchor: .leading).combined(with: .opacity),
            removal: .scale(scale: 0.96, anchor: .leading)
                .combined(with: .opacity)
                .animation(LabcordMotion.press.animation)
        )
    }
}

private struct LabcordSetupSmallChip: View {
    let label: String
    let onDismiss: () -> Void

    private let layout = LayoutTokens()

    var body: some View {
        HStack(spacing: layout.spacing4) {
            Text(label)
                .typography(Typography.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onDismiss) {
                LabcordIconArtwork(icon: .x, size: 14, relativeTo: .subheadline)
            }
            .buttonStyle(LabcordPlainButtonStyle())
            .accessibilityLabel(Text("\(label) 제거"))
        }
        .foregroundStyle(Color("General/Label/Brand", bundle: .module))
        .padding(.horizontal, layout.spacing12)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
        .background(Color("General/Fill/Selected", bundle: .module), in: Capsule())
        .contentShape(Capsule())
    }
}

private struct LabcordChipFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            width = proposedWidth
        } else {
            let itemWidths = subviews.reduce(CGFloat.zero) {
                $0 + $1.sizeThatFits(.unspecified).width
            }
            width = itemWidths + spacing * CGFloat(max(0, subviews.count - 1))
        }
        let rows = makeRows(width: width, subviews: subviews)
        let rowHeights = rows.map { row in
            row.reduce(CGFloat.zero) {
                max($0, measuredSize(for: subviews[$1], maxWidth: width).height)
            }
        }
        return CGSize(
            width: width,
            height: rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rowHeights.count - 1))
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(width: bounds.width, subviews: subviews)
        var currentY = bounds.minY

        for row in rows {
            let rowHeight = row.reduce(CGFloat.zero) {
                max($0, measuredSize(for: subviews[$1], maxWidth: bounds.width).height)
            }
            var currentX = bounds.minX
            for index in row {
                let size = measuredSize(for: subviews[index], maxWidth: bounds.width)
                subviews[index].place(
                    at: CGPoint(x: currentX, y: currentY + (rowHeight - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                currentX += size.width + spacing
            }
            currentY += rowHeight + spacing
        }
    }

    private func makeRows(width: CGFloat, subviews: Subviews) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var currentWidth: CGFloat = 0

        for index in subviews.indices {
            let itemWidth = measuredSize(for: subviews[index], maxWidth: width).width
            let proposedWidth = currentWidth == 0 ? itemWidth : currentWidth + spacing + itemWidth
            if currentWidth > 0, proposedWidth > width {
                rows.append([])
                currentWidth = itemWidth
            } else {
                currentWidth = proposedWidth
            }
            rows[rows.count - 1].append(index)
        }
        return rows.filter { !$0.isEmpty }
    }

    private func measuredSize(for subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let intrinsicSize = subview.sizeThatFits(.unspecified)
        guard maxWidth.isFinite, maxWidth > 0, intrinsicSize.width > maxWidth else {
            return intrinsicSize
        }

        return subview.sizeThatFits(
            ProposedViewSize(width: maxWidth, height: nil)
        )
    }
}

private struct ChipGroupPreviewItem: Identifiable {
    let id: Int
    let title: String
}

private struct ChipGroupPreviewContent: View {
    @State private var selection: Set<Int> = [0, 1, 2, 3]

    private let items = [
        ChipGroupPreviewItem(id: 0, title: "필터"),
        ChipGroupPreviewItem(id: 1, title: "조건"),
        ChipGroupPreviewItem(id: 2, title: "분석"),
        ChipGroupPreviewItem(id: 3, title: "대상")
    ]

    var body: some View {
        ChipGroup(
            items: items,
            selection: $selection,
            label: \.title,
            onRemove: { _ in },
            onAdd: {}
        )
    }
}

#Preview("칩 그룹 · 기본") {
    _ = FontRegistration.register()
    return ChipGroupPreviewContent()
        .frame(width: 368)
        .padding()
}

#Preview("칩 그룹 · 큰 글자") {
    _ = FontRegistration.register()
    return ChipGroupPreviewContent()
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 368)
        .padding()
}

#Preview("칩 그룹 · 추가 항목") {
    _ = FontRegistration.register()
    return ChipGroup(
        items: [ChipGroupPreviewItem(id: 4, title: "추가 항목")],
        selection: .constant([]),
        label: \.title,
        onRemove: { _ in },
        onAdd: {}
    )
    .frame(width: 368)
    .padding()
}
