import ComposableArchitecture
import SwiftUI

struct VoiceRecordingView: View {
    let store: StoreOf<VoiceRecordingFeature>

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.76)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        Button {
                            store.send(.closeRequested)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title3.weight(.medium))
                                .frame(width: 48, height: 48)
                                .background(.white.opacity(0.12), in: Circle())
                        }
                        .accessibilityLabel("음성 기록 닫기")

                        Text(store.phase == .finished ? "녹음 내용 확인" : "녹음 중")
                            .font(.headline)

                        Spacer()
                    }

                    ScrollView {
                        Text(displayedTranscript)
                            .font(.system(size: geometry.size.height < 400 ? 24 : 30))
                            .foregroundStyle(
                                store.transcript.isEmpty
                                ? .white.opacity(0.6)
                                : .white
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if store.phase == .finished {
                        HStack(spacing: 12) {
                            Button {
                                store.send(.retakeRequested)
                            } label: {
                                Label("다시 녹음", systemImage: "arrow.uturn.backward")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(.white, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            .disabled(store.isSaving)

                            Button(store.isSaving ? "저장 중..." : "지금 저장") {
                                store.send(.saveRequested)
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.blue, in: Capsule())
                            .foregroundStyle(.white)
                            .disabled(store.isSaving)
                        }
                        if store.isAutoSavePending {
                            Text("3초 후 자동 저장돼요.")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        HStack {
                            Spacer()
                            Button {
                                store.send(.stopRequested)
                            } label: {
                                Image(systemName: "mic.fill")
                                    .font(.title2)
                                    .frame(width: 68, height: 68)
                                    .background(.blue, in: Circle())
                                    .shadow(color: .white.opacity(0.65), radius: 14)
                            }
                            .disabled(store.phase != .recording)
                            .accessibilityLabel("녹음 종료")
                            Spacer()
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(28)
                .frame(
                    width: min(max(geometry.size.width - 32, 280), 900),
                    height: min(max(geometry.size.height - 48, 280), 620)
                )
                .background(.black, in: RoundedRectangle(cornerRadius: 24))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            store.send(.overlayAppeared)
        }
        .alert(
            "음성 저장 실패",
            isPresented: Binding(
                get: { store.saveError != nil },
                set: { if !$0 { store.send(.saveErrorDismissed) } }
            )
        ) {
            Button("다시 시도") {
                store.send(.saveRequested)
            }
            Button("닫기", role: .cancel) {
                store.send(.saveErrorDismissed)
            }
        } message: {
            Text(store.saveError ?? "음성을 저장하지 못했습니다.")
        }
    }

    private var displayedTranscript: String {
        if !store.transcript.isEmpty { return store.transcript }
        switch store.phase {
        case .starting: return "녹음을 준비하고 있어요."
        case .recording: return "말씀해 주세요."
        case .stopping: return "음성 인식을 마무리하고 있어요."
        case .finished: return "녹음된 내용이 없습니다."
        case .hidden: return ""
        }
    }
}
