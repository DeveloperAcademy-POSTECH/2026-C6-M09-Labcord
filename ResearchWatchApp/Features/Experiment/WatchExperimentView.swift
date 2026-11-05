import ComposableArchitecture
import LabcordShared
import SwiftUI

struct WatchExperimentView: View {
    let store: StoreOf<WatchExperimentFeature>

    var body: some View {
        Group {
            if store.screen == .timers, store.recording.focused == nil {
                WatchTimersView(store: store)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        if store.screen == .recordCleanup {
                            recordCleanup
                        } else if let record = store.recording.focused {
                            WatchRecordView(
                                store: store.scope(state: \.recording, action: \.recording),
                                record: record
                            )
                        } else {
                            screen
                        }
                        if let message = store.message {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("안내: \(message)")
                        }
                        requestStatus
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if store.screen != .selection {
                    Button("닫기", systemImage: "xmark") {
                        if store.recording.focused != nil, store.screen != .recordCleanup {
                            store.send(.recording(.close))
                        } else {
                            store.send(.closeTapped)
                        }
                    }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .tint(.blue)
    }

    private var title: String {
        switch store.screen {
        case .selection: "내 실험"
        case .permission: "마이크 권한"
        case .countdown: "실험 준비"
        case .confirmPause: "실험 중단"
        case .confirmComplete: "실험 종료"
        case .confirmResume: "실험 재개"
        case .recordCleanup: "실험 기록"
        case .connection: "연결 상태"
        case .gestures: "제스처 연습"
        case .experiment: store.selectedTitle
        case .timers: "타이머"
        case .timerEditor: "타이머 설정"
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch store.screen {
        case .selection:
            selection
        case .experiment:
            experiment
        case .permission:
            permission
        case let .countdown(seconds):
            WatchPreparationView(value: seconds.formatted())
            Button("취소", role: .cancel) { store.send(.cancelCountdown) }
        case .confirmPause:
            Text("진행 중인 녹음·영상을 중단한 뒤 저장해요. 저장 결과는 별도로 확인해주세요.")
                .font(.caption)
            Button("기록 중단", role: .destructive) { store.send(.confirmed) }
            Button("취소", role: .cancel) { store.send(.closeTapped) }
        case .confirmComplete:
            Text("진행 중인 타이머도 함께 종료돼요. 녹음·영상과 기록 정리 결과를 확인해주세요.")
                .font(.caption)
            Button("실험 종료", role: .destructive) { store.send(.confirmed) }
            Button("취소", role: .cancel) { store.send(.closeTapped) }
        case .confirmResume:
            Text("실험을 이어할까요?")
            Button("실험 재개") { store.send(.resumeConfirmed) }
                .disabled(!store.canOperate)
            Button("취소", role: .cancel) { store.send(.closeTapped) }
        case .recordCleanup:
            recordCleanup
        case .connection:
            connection
        case .timers:
            WatchTimersView(store: store)
        case .timerEditor:
            WatchTimerEditorView(store: store)
        case .gestures:
            WatchGesturePracticeView(store: store)
        }
    }

    private var selection: some View {
        VStack(spacing: 8) {
            if store.experiments.isEmpty, store.pending == nil {
                Text("iPhone에서 실험을 준비해주세요.")
                    .font(.caption)
            }
            ForEach(store.experiments) { experiment in
                Button {
                    store.send(.selected(experiment.id))
                } label: {
                    HStack {
                        Text(experiment.title)
                            .font(.body)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .disabled(store.pending != nil)
            }
            Button("새로고침", systemImage: "arrow.clockwise") { refresh() }
                .disabled(store.pending != nil)
            Button("연결 확인", systemImage: "iphone") { store.send(.connectionTapped) }
        }
    }

    @ViewBuilder
    private var experiment: some View {
        Text(store.selectedTitle)
            .font(.headline)
            .multilineTextAlignment(.center)
        if let snapshot = store.snapshot {
            switch snapshot.experiment.status {
            case .ready:
                Button("실험 시작", systemImage: "play.fill") { store.send(.startTapped) }
                    .disabled(!store.canOperate)
            case .running:
                Text("실험 진행 중")
                Button("타이머", systemImage: "timer") { store.send(.timersTapped) }
                WatchRecordControls(store: store)
                Button("실험 중단", systemImage: "pause.fill") { store.send(.pauseTapped) }
                    .disabled(!store.canOperate)
                Button("실험 종료", role: .destructive) { store.send(.completeTapped) }
                    .disabled(!store.canOperate)
            case .paused:
                Text("실험이 중단됐어요.")
                Button("타이머 상태", systemImage: "timer") { store.send(.timersTapped) }
                WatchRecordControls(store: store)
                Button("실험 재개", systemImage: "play.fill") { store.send(.resumeTapped) }
                    .disabled(!store.canOperate)
                Button("실험 종료", role: .destructive) { store.send(.completeTapped) }
                    .disabled(!store.canOperate)
            case .completed:
                Text("실험이 종료됐어요.")
                WatchRecordControls(store: store)
                Text("기록 저장·정리 결과는 iPhone에서 확인해주세요.")
                    .font(.caption)
            }
        } else {
            Text("실험 상태 확인 필요")
        }
        Button("상태 새로고침") { refresh() }
            .disabled(store.pending != nil)
        Button("연결 확인", systemImage: store.isReachable ? "iphone" : "iphone.slash") {
            store.send(.connectionTapped)
        }
        Button("제스처 연습") { store.send(.gesturesTapped) }
        Button("실험 목록") { store.send(.backTapped) }
            .disabled(store.pending != nil
                      || store.recording.hasUnsettledRecords(in: store.selectedID))
    }

    @ViewBuilder
    private var permission: some View {
        if store.isRequestingPermission {
            WatchPreparationView(value: "준비")
        } else {
            permissionPrompt
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 8) {
            Text(store.permissionDenied ? "마이크 권한이 꺼져 있어요." : "마이크 권한 허용")
                .font(.headline)
            Text("실험 중 음성 기록을 하려면 마이크 접근이 필요해요.")
                .font(.caption)
            if store.permissionDenied {
                Text("iPhone의 Watch 앱 또는 기기 설정에서 마이크 권한을 확인하고 돌아와주세요.")
                    .font(.caption)
            }
            Button(store.permissionDenied ? "권한 다시 확인" : "허용") {
                store.send(.permissionRequested)
            }
            Button("허용하지 않음", role: .cancel) { store.send(.closeTapped) }
        }
    }

    private var connection: some View {
        VStack(spacing: 8) {
            Image(systemName: store.isReachable ? "iphone" : "exclamationmark.triangle")
                .font(.largeTitle)
            Text(store.isReachable ? "iPhone 연결됨" : "iPhone 연결 끊김")
                .font(.headline)
            Text("연결이 끊겨도 진행 중인 Watch 녹음은 계속 보관하고 재연결 후 전송해요. 저장 공간·오디오 중단 시에는 별도 안내를 확인해주세요.")
                .font(.caption)
            Text("iPhone에서 Labcord를 열어주세요. 촬영은 카메라를 준비한 뒤 다시 요청해주세요.")
                .font(.caption)
            Button("다시 연결") { refresh() }
            Button("닫기", role: .cancel) { store.send(.closeTapped) }
        }
    }

    @ViewBuilder
    private var requestStatus: some View {
        if let pending = store.pending {
            switch pending.phase {
            case .delivering:
                ProgressView("전달 확인 중")
            case .processing:
                ProgressView("iPhone 처리 중")
                Text("전달은 확인됐어요. 처리·저장 완료와는 달라요.")
                    .font(.caption)
            case .uncertain:
                Text("요청 결과 확인 필요")
                    .font(.caption)
            }
            Button("요청 상태 확인") { store.send(.checkRequest) }
                .disabled(!store.isReachable)
            if pending.command.operation == .cancelRecord, store.canRetryPendingCancellation {
                Button("같은 취소 요청 다시 전송") { store.send(.retryPendingCancellation) }
                    .disabled(!store.isReachable)
            }
        }
    }

    private func refresh() {
        store.send(store.isVisible ? .refresh : .appeared)
    }
}
