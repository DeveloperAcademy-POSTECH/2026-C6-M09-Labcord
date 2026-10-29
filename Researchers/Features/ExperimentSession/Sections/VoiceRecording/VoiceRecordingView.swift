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
                        HStack {
                            Spacer()
                            Button {
                                store.send(.retakeRequested)
                            } label: {
                                Label("다시하기", systemImage: "arrow.uturn.backward")
                                    .font(.headline)
                                    .padding(.horizontal, 24)
                                    .frame(height: 52)
                                    .background(.white, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            .accessibilityLabel("음성 다시 녹음")
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
