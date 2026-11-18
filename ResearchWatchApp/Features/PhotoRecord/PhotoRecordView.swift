import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import OSLog
import SwiftUI

private let watchPhotoCancelLog = Logger(
    subsystem: "com.researchers.Researchers.watchkitapp", category: "WatchPhotoCancel"
)

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
                    if store.phase == .saving {
                        Text("저장 중")
                    } else {
                        Text(store.requests.lastRecord?.phase == .capturing ? "촬영 중" : "촬영 요청 중")
                    }
                    ProgressView()
                        .progressViewStyle(.circular)
                        .fixedSize()
                    if store.phase == .saving, !store.requests.isWaiting(for: .confirmRecord) {
                        Button("저장 다시 시도") { store.send(.saveTapped) }
                    } else if store.phase == .capturing, store.recordID != nil,
                              !store.requests.isWaiting(for: .takePhoto) {
                        Button("촬영 상태 확인") { store.send(.retryTapped) }
                    }
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
                ProgressView("취소 중")

            case .captureFailed, .cancelFailed:
                VStack(spacing: 8) {
                    Text(store.phase == .cancelFailed ? "취소를 확인할 수 없어요" : "촬영을 확인할 수 없어요")
                    Button("다시 시도") { store.send(.retryTapped) }
                }
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
                    if store.phase == .saved {
                        watchPhotoCancelLog.info("X after saved")
                        dismiss()
                    } else {
                        watchPhotoCancelLog.info("X before saved")
                        store.send(.closeTapped)
                    }
                } label: {
                    Image(systemName: "xmark")
                }
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
