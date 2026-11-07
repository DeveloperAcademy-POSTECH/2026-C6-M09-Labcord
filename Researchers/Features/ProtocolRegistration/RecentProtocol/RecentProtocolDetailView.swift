import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct RecentProtocolDetailView: View {
    private let title: String
    private let timerSeconds: [Int]
    private let groups: [(String, [String])]
    private let select: () -> Void
    @State private var expandedGroups: Set<String> = []

    init(entry: RecentProtocolEntry, select: @escaping () -> Void) {
        self.init(
            title: entry.title,
            timerSeconds: entry.timerSeconds,
            groups: [
                ("시약·재료", entry.materials), ("샘플·분석 대상", entry.samples),
                ("실험 용어", entry.glossaryTerms), ("단위", entry.units)
            ],
            select: select
        )
    }

    fileprivate init(
        title: String, timerSeconds: [Int], groups: [(String, [String])],
        select: @escaping () -> Void
    ) {
        self.title = title
        self.timerSeconds = timerSeconds
        self.groups = groups
        self.select = select
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text(title).typography(Typography.title2Bold)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("타이머").typography(Typography.calloutSemiBold)
                            Text("\(timerSeconds.count)")
                                .typography(Typography.subheadline)
                                .foregroundStyle(Color(
                                    "General/Label/Tertiary",
                                    bundle: LabcordDesignSystemResources.bundle
                                ))
                        }
                        if timerSeconds.isEmpty {
                            Text("타이머가 없어요")
                        } else {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 12), count: 3
                                ),
                                spacing: 12
                            ) {
                                ForEach(
                                    Array(timerSeconds.enumerated()), id: \.offset
                                ) { item in
                                    ProtocolTimerRow(
                                        duration: .seconds(item.element),
                                        rows: item.element >= 3_600 ? .two : .one,
                                        showEditButton: false
                                    )
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("추출한 용어").typography(Typography.calloutSemiBold)
                        Text("프로토콜에서 추출한 전문 용어를 음성 인식에 반영해요.")
                            .typography(Typography.subheadline)
                            .foregroundStyle(Color(
                                "General/Label/Secondary",
                                bundle: LabcordDesignSystemResources.bundle
                            ))
                        ForEach(groups, id: \.0) { title, terms in
                            Accordion(title, count: terms.count, isExpanded: Binding(
                                get: { expandedGroups.contains(title) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedGroups.insert(title)
                                    } else {
                                        expandedGroups.remove(title)
                                    }
                                }
                            )) {
                                if terms.isEmpty {
                                    Text("용어가 없어요").typography(Typography.subheadline)
                                } else {
                                    RecentTermFlow(spacing: 12) {
                                        ForEach(Array(terms.enumerated()), id: \.offset) { term in
                                            Text(term.element)
                                                .typography(Typography.subheadline)
                                                .foregroundStyle(Color(
                                                    "General/Label/Brand",
                                                    bundle: LabcordDesignSystemResources.bundle
                                                ))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(Color(
                                                    "General/Fill/Selected",
                                                    bundle: LabcordDesignSystemResources.bundle
                                                ), in: Capsule())
                                                .overlay {
                                                    Capsule().strokeBorder(Color(
                                                        "General/Border/Focused",
                                                        bundle: LabcordDesignSystemResources.bundle
                                                    ))
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: select) {
                    Text("프로토콜 선택").frame(maxWidth: .infinity)
                }
                    .buttonStyle(.labcord(.primary, size: .large))
                    .padding(16)
            }
            .navigationTitle("프로토콜 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

private struct RecentTermFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) {
            $0 + $1.sizeThatFits(.unspecified).width
        }
        let rows = rows(for: width, subviews: subviews)
        return CGSize(width: width, height: rows.reduce(0) { $0 + $1.height }
                      + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var originY = bounds.minY
        for row in rows(for: bounds.width, subviews: subviews) {
            var originX = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(
                    ProposedViewSize(width: bounds.width, height: nil)
                )
                subviews[index].place(
                    at: CGPoint(x: originX, y: originY), proposal: ProposedViewSize(size)
                )
                originX += size.width + spacing
            }
            originY += row.height + spacing
        }
    }

    private func rows(
        for width: CGFloat, subviews: Subviews
    ) -> [(indices: [Int], height: CGFloat)] {
        var result: [(indices: [Int], height: CGFloat)] = []
        var indices: [Int] = []
        var occupied: CGFloat = 0
        var height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !indices.isEmpty && occupied + spacing + size.width > width {
                result.append((indices, height))
                indices = []
                occupied = 0
                height = 0
            }
            occupied += (indices.isEmpty ? 0 : spacing) + size.width
            indices.append(index)
            height = max(height, size.height)
        }
        if !indices.isEmpty { result.append((indices, height)) }
        return result
    }
}

#Preview("최근 프로토콜 상세") {
    let _ = FontRegistration.register()
    NavigationStack {
        RecentProtocolDetailView(
            title: "촉매 반응 조건 비교 실험",
            timerSeconds: [600, 30, 60, 86_399],
            groups: [
                ("시약·재료", ["시약", "완충액"]),
                ("샘플·분석 대상", ["샘플"]),
                ("실험 용어", ["촉매"]),
                ("단위", ["mL"])
            ],
            select: {}
        )
    }
}
