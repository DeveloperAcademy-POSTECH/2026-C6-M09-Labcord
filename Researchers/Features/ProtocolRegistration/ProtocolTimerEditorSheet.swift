import LabcordDesignSystem
import SwiftUI

struct ProtocolTimerEditorSheet: View {
    let editor: TimerEditor
    let onConfirm: (Int?, Int) -> Void
    let onDelete: (Int?) -> Void
    let onCancel: () -> Void

    var body: some View {
        if editor.duration.components.seconds >= 86_400 {
            LongTimerEditorSheet(
                editor: editor, onConfirm: onConfirm, onDelete: onDelete, onCancel: onCancel
            )
        } else {
            TimerEditorSheet(
                editor: editor, onConfirm: onConfirm, onDelete: onDelete, onCancel: onCancel
            )
        }
    }
}

private struct LongTimerEditorSheet: View {
    let editor: TimerEditor
    let onConfirm: (Int?, Int) -> Void
    let onDelete: (Int?) -> Void
    let onCancel: () -> Void
    @State private var hours: String
    @State private var minutes: String
    @State private var seconds: String
    @State private var invalidDuration = false

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
        let total = editor.duration.components.seconds
        _hours = State(initialValue: String(total / 3_600))
        _minutes = State(initialValue: String(total / 60 % 60))
        _seconds = State(initialValue: String(total % 60))
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("취소", action: onCancel)
                Spacer()
                Text("타이머 수정").typography(Typography.bodySemiBold)
                Spacer()
                Button("삭제") { onDelete(editor.index) }
            }
            HStack {
                field("시간", value: $hours)
                field("분", value: $minutes)
                field("초", value: $seconds)
            }
            Button("저장", action: save)
                .buttonStyle(.labcord(.primary, size: .large))
                .disabled(isUnchanged)
        }
        .padding(16)
        .alert("타이머 시간을 확인해 주세요", isPresented: $invalidDuration) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("1초 이상으로 설정하고 분과 초는 0부터 59까지 입력해 주세요. 시간이 너무 크면 줄여 주세요.")
        }
    }

    private func field(_ label: String, value: Binding<String>) -> some View {
        VStack {
            Text(label)
            TextField(label, text: value)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var isUnchanged: Bool {
        guard let hours = Int(hours), let minutes = Int(minutes), let seconds = Int(seconds),
              (0...59).contains(minutes), (0...59).contains(seconds) else { return false }
        let (hourSeconds, overflow) = hours.multipliedReportingOverflow(by: 3_600)
        let (total, sumOverflow) = hourSeconds.addingReportingOverflow(minutes * 60 + seconds)
        return !overflow && !sumOverflow && total == editor.duration.components.seconds
    }

    private func save() {
        guard let hours = Int(hours), hours >= 0,
              let minutes = Int(minutes), (0...59).contains(minutes),
              let seconds = Int(seconds), (0...59).contains(seconds) else {
            invalidDuration = true
            return
        }
        let (hourSeconds, overflow) = hours.multipliedReportingOverflow(by: 3_600)
        let (total, sumOverflow) = hourSeconds.addingReportingOverflow(minutes * 60 + seconds)
        guard !overflow, !sumOverflow,
              (1...ProtocolReviewFeature.maximumTimerSeconds).contains(total) else {
            invalidDuration = true
            return
        }
        onConfirm(editor.index, total)
    }
}

struct TimerEditor: Identifiable {
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
    @State private var invalidDuration = false
    @ScaledMetric(relativeTo: .body) private var headerControlScale: CGFloat = 1

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
        VStack(spacing: 16) {
            Capsule()
                .fill(Color(
                    "General/Timer/Sheet/Grabber", bundle: LabcordDesignSystemResources.bundle
                ))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)
            HStack {
                Button(action: onCancel) {
                    Image(labcordIcon: .x)
                        .resizable()
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.labcordIcon(.plain, size: .large))
                .accessibilityLabel("닫기")
                Text(editor.index == nil ? "타이머 추가" : "타이머 수정")
                    .typography(Typography.bodySemiBold)
                    .frame(maxWidth: .infinity)
                Color.clear
                    .frame(width: 50 * headerControlScale, height: 50 * headerControlScale)
                    .accessibilityHidden(true)
            }
            TimerPicker(duration: $duration, usage: .setup)
            HStack(spacing: 16) {
                Button(role: .destructive) { onDelete(editor.index) } label: {
                    Text("삭제").frame(maxWidth: .infinity)
                }
                .buttonStyle(.labcord(.quaternary, size: .large))
                Button {
                    let seconds = Int(duration.components.seconds)
                    guard (1...86_399).contains(seconds) else {
                        invalidDuration = true
                        return
                    }
                    onConfirm(editor.index, seconds)
                } label: {
                    Text("저장").frame(maxWidth: .infinity)
                }
                .buttonStyle(.labcord(.primary, size: .large))
                .disabled(editor.index != nil && duration == editor.duration)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .alert("타이머 시간을 확인해 주세요", isPresented: $invalidDuration) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("1초부터 23시간 59분 59초까지 설정해 주세요.")
        }
    }
}

#Preview("타이머 추가") {
    _ = FontRegistration.register()
    ProtocolTimerEditorSheet(
        editor: TimerEditor(index: nil, duration: .zero),
        onConfirm: { _, _ in },
        onDelete: { _ in },
        onCancel: {}
    )
}

#Preview("타이머 수정") {
    _ = FontRegistration.register()
    ProtocolTimerEditorSheet(
        editor: TimerEditor(index: 0, duration: .seconds(600)),
        onConfirm: { _, _ in },
        onDelete: { _ in },
        onCancel: {}
    )
}

#Preview("긴 타이머 수정") {
    _ = FontRegistration.register()
    ProtocolTimerEditorSheet(
        editor: TimerEditor(index: 0, duration: .seconds(90_000)),
        onConfirm: { _, _ in },
        onDelete: { _ in },
        onCancel: {}
    )
}
