import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import SwiftUI

struct PhotoRecordView: View {
    let store: StoreOf<PhotoRecordFeature>
    @Binding var presentedPhoto: StoreOf<PhotoRecordFeature>?

    private var countdown: WatchPhotoCountdown? {
        guard let recordID = store.recordID else { return nil }
        return WatchPhotoCountdown(
            screen: store.phoneScreen, experimentID: store.experimentID, recordID: recordID
        )
    }

    var body: some View {
        VStack {
            switch store.phase {
            case .capturing, .saving:
                VStack(spacing: 4) {
                    PhotoCountdownLabel(
                        countdown: store.phase == .capturing ? countdown : nil,
                        fallback: store.phase == .capturing ? "촬영 중" : "저장 중"
                    )
                    ProgressView()
                        .progressViewStyle(.circular)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .recovering:
                ProgressView {
                    PhotoCountdownLabel(countdown: countdown, fallback: "촬영 상태 확인 중")
                }
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
        .onChange(of: store.shouldDismiss, initial: true) { _, shouldDismiss in
            if shouldDismiss, presentedPhoto === store { presentedPhoto = nil }
        }
        .task(id: store.phase) {
            guard store.phase == .saved else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, store.phase == .saved else { return }
            store.send(.closeTapped)
        }
    }
}

#Preview {
    let store = Store(initialState: PhotoRecordFeature.State(experimentID: UUID())) {
        PhotoRecordFeature()
    }
    PhotoRecordView(store: store, presentedPhoto: .constant(store))
}
