import ComposableArchitecture
import LabcordShared
import SwiftUI

struct WatchTimersView: View {
    let store: StoreOf<WatchExperimentFeature>

    var body: some View {
        List {
            if let snapshot = store.snapshot {
                Text("진행 중인 타이머")
                    .font(.system(size: 13, weight: .medium))
                Button("타이머 추가", systemImage: "plus") {
                    store.send(.timerEditorTapped)
                }
                .disabled(!canModify)
                if snapshot.timers.isEmpty {
                    Text("진행 중인 타이머가 없어요.")
                        .font(.caption)
                }
                ForEach(snapshot.timers) { timer in
                    WatchTimerRow(timer: timer, canOperate: canModify) { operation in
                        switch operation {
                        case .pause: store.send(.timerPaused(timer.id))
                        case .resume: store.send(.timerResumed(timer.id))
                        case .finish: store.send(.timerDeleted(timer.id))
                        }
                    }
                }
                if snapshot.mode == .procedure {
                    Text("프로토콜 타이머")
                        .font(.system(size: 13, weight: .medium))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        ForEach(protocolDurations) { choice in
                            Button {
                                store.send(.timerStarted(choice.seconds))
                            } label: {
                                Text(choice.seconds % 60 == 0
                                     ? "\(choice.seconds / 60)\n분"
                                     : WatchPresentationRules.time(choice.seconds))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .disabled(!canModify || choice.seconds <= 0)
                        }
                    }
                }
            }
            if let message = store.message { Text(message).font(.caption) }
            if let pending = store.pending {
                Text(pending.phase == .processing ? "iPhone 처리 중" : "요청 결과 확인 중")
                Button("요청 상태 확인") { store.send(.checkRequest) }
                    .disabled(!store.isReachable)
            }
        }
    }

    private var protocolDurations: [WatchPresentationRules.ProtocolTimerChoice] {
        WatchPresentationRules.protocolTimerChoices(store.snapshot?.protocolTimerSeconds ?? [])
    }

    private var canModify: Bool {
        store.canOperate && store.snapshot?.experiment.status == .running
    }
}

private struct WatchTimerRow: View {
    enum Operation {
        case pause
        case resume
        case finish
    }

    let timer: WatchTimerSnapshot
    let canOperate: Bool
    let action: (Operation) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(durationLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(WatchPresentationRules.time(timer.remaining(at: context.date)))
                        .font(.system(size: 16, weight: .medium).monospacedDigit())
                }
            }
            Spacer(minLength: 2)
            Button {
                switch timer.status {
                case .running: action(.pause)
                case .paused: action(.resume)
                case .finished: action(.finish)
                }
            } label: {
                Image(systemName: buttonSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(buttonColor, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(buttonLabel)
            .disabled(!canOperate)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(rowColor)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(status)
        .accessibilityAction(named: Text("타이머 종료")) {
            if canOperate { action(.finish) }
        }
        .swipeActions {
            Button("삭제", role: .destructive) { action(.finish) }
                .disabled(!canOperate)
        }
    }

    private var buttonColor: Color {
        timer.status == .finished ? .orange : .blue
    }

    private var durationLabel: String {
        let seconds = timer.durationSeconds
        if seconds >= 3600, seconds % 60 == 0 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분"
        }
        if seconds > 0, seconds % 60 == 0 { return "\(seconds / 60)분" }
        return WatchPresentationRules.time(seconds)
    }

    private var rowColor: Color {
        timer.status == .finished ? .orange.opacity(0.2) : .white.opacity(0.14)
    }

    private var buttonSymbol: String {
        switch timer.status {
        case .running: "pause.fill"
        case .paused: "play.fill"
        case .finished: "xmark"
        }
    }

    private var buttonLabel: String {
        switch timer.status {
        case .running: "타이머 일시정지"
        case .paused: "타이머 재개"
        case .finished: "완료 확인"
        }
    }

    private var status: String {
        switch timer.status {
        case .running: "실행 중"
        case .paused: "일시정지"
        case .finished: "완료"
        }
    }
}

struct WatchTimerEditorView: View {
    let store: StoreOf<WatchExperimentFeature>

    var body: some View {
        VStack {
            HStack(spacing: 2) {
                wheel("시간", value: store.timerHours, range: 0..<24) {
                    store.send(.timerHoursChanged($0))
                }
                separator
                wheel("분", value: store.timerMinutes, range: 0..<60) {
                    store.send(.timerMinutesChanged($0))
                }
                separator
                wheel("초", value: store.timerSeconds, range: 0..<60) {
                    store.send(.timerSecondsChanged($0))
                }
            }
            .frame(height: 100)
            Button("타이머 실행") { store.send(.customTimerStarted) }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!store.canOperate || duration == 0)
            Button("취소", role: .cancel) { store.send(.timersTapped) }
        }
    }

    private var duration: Int {
        store.timerHours * 3600 + store.timerMinutes * 60 + store.timerSeconds
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: 24))
            .accessibilityHidden(true)
    }

    private func wheel(
        _ title: String, value: Int, range: Range<Int>, change: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption2)
                .accessibilityHidden(true)
            Picker(title, selection: Binding(get: { value }, set: change)) {
                ForEach(range, id: \.self) { Text($0.formatted()).tag($0) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
