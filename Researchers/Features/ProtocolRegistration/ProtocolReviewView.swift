import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct ProtocolReviewView: View {
    @Bindable var store: StoreOf<ProtocolReviewFeature>
    @State private var timerEditor: TimerEditor?
    @FocusState private var titleFocused: Bool
    @FocusState private var termFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                titleField
                timerSection
                termSection
            }
            .padding(16)
        }
        .labcordDismissKeyboardOnTapOutside()
        .onChange(of: termFocused) { _, focused in
            if !focused { store.send(.endTermEditing) }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if !store.timersValid {
                    Text("시간이 너무 긴 타이머를 수정하거나 삭제해 주세요.")
                        .typography(Typography.subheadline)
                }
                Button {
                    store.send(.registerTapped)
                } label: {
                    Text("실험 등록").frame(maxWidth: .infinity)
                }
                .buttonStyle(.labcord(.primary, size: .large))
                .disabled(!store.titleValid || !store.timersValid || store.hasUncommittedTerm)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .background(Color(
                "General/Background/Primary", bundle: LabcordDesignSystemResources.bundle
            ))
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            NavigationPageTitle("프로토콜 분석 결과") {
                store.send(.backTapped)
            }
            .background {
                Color("General/Background/Primary", bundle: LabcordDesignSystemResources.bundle)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .sheet(item: $timerEditor) { editor in
            ProtocolTimerEditorSheet(editor: editor) { index, seconds in
                store.send(.saveTimer(index, seconds))
                timerEditor = nil
            } onDelete: { index in
                if let index { store.send(.deleteTimer(index)) }
                timerEditor = nil
            } onCancel: {
                timerEditor = nil
            }
            .id(editor.id)
            .presentationDetents([.height(370)])
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("실험 이름 ").foregroundStyle(Color(
                    "General/Label/Secondary", bundle: LabcordDesignSystemResources.bundle
                ))
                Text("*").foregroundStyle(Color(
                    "General/Feedback/Error/Foreground",
                    bundle: LabcordDesignSystemResources.bundle
                ))
            }
            .typography(Typography.calloutSemiBold)
            .accessibilityElement(children: .combine)
            TextField("실험 이름을 입력해 주세요.", text: Binding(
                get: { store.title }, set: { store.send(.titleChanged($0)) }
            ))
            .labcordTextFieldStyle(
                text: store.title, focus: $titleFocused, isError: store.titleError != nil
            )
            HStack(spacing: 8) {
                if store.title.isEmpty || store.titleError != nil {
                    Text("최대 60자까지 입력할 수 있습니다.")
                        .typography(Typography.subheadline)
                        .foregroundStyle(Color(
                            store.titleError == nil
                                ? "General/Label/Secondary" : "General/Feedback/Error/Foreground",
                            bundle: LabcordDesignSystemResources.bundle
                        ))
                }
                Spacer()
                Text("\(store.title.count)/60")
                    .typography(Typography.subheadline)
                    .foregroundStyle(Color(
                        store.titleError == nil
                            ? "General/Label/Tertiary" : "General/Feedback/Error/Foreground",
                        bundle: LabcordDesignSystemResources.bundle
                    ))
            }
        }
    }

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("타이머").typography(Typography.calloutSemiBold)
                Text("\(store.timerSeconds.count)")
                    .foregroundStyle(Color(
                        "General/Label/Tertiary", bundle: LabcordDesignSystemResources.bundle
                    ))
                Spacer()
                Button("추가") { openTimer(index: nil) }
                    .buttonStyle(.labcord(.accent, size: .small))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)) {
                ForEach(Array(store.timerSeconds.enumerated()), id: \.offset) { index, seconds in
                    ProtocolTimerRow(.seconds(seconds)) { openTimer(index: index) }
                }
            }
        }
    }

    private var termSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("추출한 용어").typography(Typography.calloutSemiBold)
            Text("프로토콜에서 추출한 전문 용어를 음성 인식에 반영해요.")
                .typography(Typography.subheadline)
                .foregroundStyle(Color(
                    "General/Label/Secondary", bundle: LabcordDesignSystemResources.bundle
                ))
            ForEach(ProtocolTermCategory.allCases, id: \.self) { category in
                Accordion(category.title, count: store.terms[category, default: []].count,
                          isExpanded: Binding(
                            get: { store.expanded.contains(category) },
                            set: { store.send(.expandedChanged(category, $0)) }
                          )) {
                    VStack(alignment: .leading, spacing: 12) {
                        TermFlowLayout(spacing: 12) {
                            ForEach(store.terms[category, default: []]) { term in
                                ChipGroup(
                                    [term],
                                    label: { $0.value },
                                    onRemove: { store.send(.removeTerm(category, $0.id)) }
                                )
                            }
                            if store.inputCategory != category {
                                Button {
                                    store.send(.editTerm(category))
                                    termFocused = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(labcordIcon: .plus)
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                        Text("추가")
                                    }
                                }
                                .buttonStyle(.labcord(.accent, size: .small))
                                .disabled(store.hasUncommittedTerm)
                                .labcordKeyboardDismissalDisabled()
                            }
                        }
                        if store.inputCategory == category {
                            termInput
                        }
                    }
                }
            }
        }
    }

    private var termInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("용어 입력", text: Binding(
                get: { store.termInput }, set: { store.send(.termChanged($0)) }
            ))
            .labcordTextFieldStyle(
                text: store.termInput, focus: $termFocused, isError: store.termError != nil
            )
            .submitLabel(.done)
            .onSubmit {
                store.send(.addTerm)
                termFocused = true
            }
            HStack {
                if let error = store.termError { Text(error) }
                Spacer()
                Text("\(store.termCharacterCount)/22")
            }
            .typography(Typography.subheadline)
            .foregroundStyle(Color(
                store.termError == nil
                    ? "General/Label/Tertiary" : "General/Feedback/Error/Foreground",
                bundle: LabcordDesignSystemResources.bundle
            ))
        }
    }

    private func openTimer(index: Int?) {
        timerEditor = TimerEditor(
            index: index, duration: .seconds(index.map { store.timerSeconds[$0] } ?? 0)
        )
    }
}

private struct TermFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) {
            $0 + $1.sizeThatFits(.unspecified).width + spacing
        }
        return arrange(subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        guard !subviews.isEmpty else { return (.zero, []) }
        let availableWidth = max(0, width)
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let intrinsic = subview.sizeThatFits(.unspecified)
            let size = intrinsic.width > availableWidth
                ? subview.sizeThatFits(ProposedViewSize(width: availableWidth, height: nil))
                : intrinsic
            if x > 0 && x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: availableWidth, height: y + rowHeight), frames)
    }
}

#Preview("프로토콜 분석 결과") {
    let _ = FontRegistration.register()
    let terms: [ProtocolTermCategory: [ProtocolReviewTerm]] = [
        .materials: [
            ProtocolReviewTerm(id: UUID(), value: "시약"),
            ProtocolReviewTerm(id: UUID(), value: "완충액")
        ],
        .samples: [ProtocolReviewTerm(id: UUID(), value: "샘플")]
    ]
    NavigationStack {
        ProtocolReviewView(
            store: Store(initialState: ProtocolReviewFeature.State(
                title: "촉매 반응 조건 비교 실험",
                timerSeconds: [15, 30, 60, 86_399],
                terms: terms,
                expanded: [.materials]
            )) {
                ProtocolReviewFeature()
            }
        )
    }
}

#Preview("프로토콜 분석 결과 · 빈 입력") {
    let _ = FontRegistration.register()
    NavigationStack {
        ProtocolReviewView(
            store: Store(initialState: ProtocolReviewFeature.State(
                title: "", timerSeconds: [], terms: [:]
            )) {
                ProtocolReviewFeature()
            }
        )
    }
}
