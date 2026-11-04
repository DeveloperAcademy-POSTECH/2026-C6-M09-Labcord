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
            .background {
                Color.clear.contentShape(Rectangle()).onTapGesture {
                    titleFocused = false
                    termFocused = false
                    store.send(.endTermEditing)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if store.hasUncommittedTerm {
                    Text("입력한 용어를 추가하거나 지운 뒤 등록해 주세요.")
                        .typography(Typography.subheadline)
                }
                Button {
                    store.send(.registerTapped)
                } label: {
                    Text("실험 등록").frame(maxWidth: .infinity)
                }
                .buttonStyle(.labcord(.primary, size: .large))
                .disabled(!store.titleValid || store.hasUncommittedTerm)
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
            TimerEditorSheet(editor: editor) { index, seconds in
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
                Text("실험 이름 ")
                Text("*").foregroundStyle(Color(
                    "General/Feedback/Error/Foreground",
                    bundle: LabcordDesignSystemResources.bundle
                ))
            }
            .typography(Typography.calloutSemiBold)
            .accessibilityElement(children: .combine)
            TextField("실험 이름을 입력해 주세요", text: Binding(
                get: { store.title }, set: { store.send(.titleChanged($0)) }
            ))
            .labcordTextFieldStyle(
                text: store.title, focus: $titleFocused, isError: store.titleError != nil
            )
            HStack {
                if let error = store.titleError {
                    Text(error)
                        .foregroundStyle(Color(
                            "General/Feedback/Error/Foreground",
                            bundle: LabcordDesignSystemResources.bundle
                        ))
                }
                Spacer()
                Text("\(store.title.count)/60")
                    .typography(Typography.subheadline)
                    .foregroundStyle(Color(
                        "General/Label/Tertiary", bundle: LabcordDesignSystemResources.bundle
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
                    ChipGroup(
                        store.terms[category, default: []],
                        label: { $0.value },
                        onRemove: { store.send(.removeTerm(category, $0.id)) },
                        onAdd: addTermAction(for: category)
                    )
                    if store.inputCategory == category {
                        termInput
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
            .submitLabel(.return)
            .onSubmit {
                store.send(.addTerm)
                termFocused = true
            }
            HStack {
                if let error = store.termError { Text(error) }
                Spacer()
                Text("\(store.termInput.count)/22")
            }
            .typography(Typography.subheadline)
            .foregroundStyle(Color(
                store.termError == nil
                    ? "General/Label/Tertiary" : "General/Feedback/Error/Foreground",
                bundle: LabcordDesignSystemResources.bundle
            ))
        }
    }

    private func addTermAction(for category: ProtocolTermCategory) -> (() -> Void)? {
        guard store.inputCategory != category else { return nil }
        return {
            store.send(.editTerm(category))
            termFocused = true
        }
    }

    private func openTimer(index: Int?) {
        timerEditor = TimerEditor(
            index: index, duration: .seconds(index.map { store.timerSeconds[$0] } ?? 0)
        )
    }
}

private struct TimerEditor: Identifiable {
    let id = UUID()
    let index: Int?
    let duration: Duration
}

private struct TimerEditorSheet: View {
    let editor: TimerEditor
    let onConfirm: (Int?, Int) -> Void
    let onDelete: (Int?) -> Void
    let onCancel: () -> Void
    @State private var duration: Duration

    init(
        editor: TimerEditor,
        onConfirm: @escaping (Int?, Int) -> Void,
        onDelete: @escaping (Int?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.editor = editor
        self.onConfirm = onConfirm
        self.onDelete = onDelete
        self.onCancel = onCancel
        _duration = State(initialValue: editor.duration)
    }

    var body: some View {
        TimerSettingSheet(duration: $duration) {
            onCancel()
        } onDelete: {
            onDelete(editor.index)
        } onConfirm: {
            onConfirm(editor.index, Int(duration.components.seconds))
        }
    }
}
