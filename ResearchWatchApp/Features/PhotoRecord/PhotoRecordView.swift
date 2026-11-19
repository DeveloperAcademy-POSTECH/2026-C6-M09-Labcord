import ComposableArchitecture
import LabcordDesignSystem
import LabcordWatchOS
import SwiftUI

struct PhotoRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store: StoreOf<PhotoRecordFeature>

    init(experimentID: UUID) {
        _store = State(initialValue: Store(
            initialState: PhotoRecordFeature.State(experimentID: experimentID)
        ) {
            PhotoRecordFeature()
        })
    }

    var body: some View {
        VStack {
            switch store.phase {
            case .capturing, .saving:
                VStack(spacing: 4) {
                    Text(store.phase == .capturing ? "촬영 중" : "저장 중")
                    ProgressView()
                        .progressViewStyle(.circular)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .recovering:
                ProgressView("촬영 상태 확인 중")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed:
                VStack(spacing: 8) {
                    Text("사진 촬영에 실패했어요")
                    Button("다시 시도") { store.send(.retryTapped) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .review:
                TranScriptView(
                    transcript: "해당 장면을\n저장할까요?",
                    isSavePrompt: true,
                    autoSaveSeconds: store.autoSaveSeconds,
                    onRerecord: { store.send(.retakeTapped) },
                    onSave: { store.send(.saveTapped) }
                )

            case .saved:
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color("General/Brand/Primary"))
                    Text("저장 완료")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .closing:
                Color.clear
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(
            [.review, .saved, .closing].contains(store.phase) ? "" : "사진 촬영"
        )
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    store.send(.closeTapped)
                } label: {
                    Image(systemName: "xmark")
                }
                .disabled(store.phase == .saving || store.phase == .closing)
            }
        }
        .interactiveDismissDisabled(store.phase != .saved)
        .onAppear { store.send(.appeared) }
        .onDisappear { store.send(.disappeared) }
        .onChange(of: store.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .task(id: store.phase) {
            guard store.phase == .saved else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, store.phase == .saved else { return }
            dismiss()
        }
    }
}

#Preview {
    PhotoRecordView(experimentID: UUID())
}
