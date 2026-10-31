import LabcordDesignSystem
import SwiftUI

struct CatalogTimerIdentityScenario: View {
    @State private var session = CatalogIdentitySession()
    @State private var reversesOrder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("새 타이머는 진행 중인 타이머가 쓰지 않는 색을 우선해요.")
                .typography(Typography.footnote)
                .foregroundStyle(.labcord(.labelSecondary))

            ViewThatFits(in: .horizontal) {
                HStack { sessionButtons }
                VStack(alignment: .leading) { sessionButtons }
            }
            .buttonStyle(.labcord(.secondary, size: .small))

            ForEach(visibleTimers) { timer in
                timerRow(timer)
            }

            Text("기록 \(session.records.count)개")
                .typography(Typography.calloutSemiBold)
                .accessibilityIdentifier("catalog.timerIdentity.recordCount")
            ForEach(session.records) { record in
                recordRow(record)
            }
        }
    }

    private var visibleTimers: [CatalogIdentityTimer] {
        reversesOrder ? Array(session.timers.reversed()) : session.timers
    }

    @ViewBuilder
    private var sessionButtons: some View {
        Button("타이머 추가") { session.addTimer() }
            .accessibilityIdentifier("catalog.timerIdentity.add")
        Button("정렬 반전") { reversesOrder.toggle() }
            .accessibilityIdentifier("catalog.timerIdentity.reorder")
        Button("새 세션") { session = CatalogIdentitySession() }
            .accessibilityHint(Text("이 시연의 타이머와 기록을 초기화합니다"))
            .accessibilityIdentifier("catalog.timerIdentity.reset")
    }

    private func timerRow(_ timer: CatalogIdentityTimer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let identity = session.identities[timer.id] {
                    Circle()
                        .fill(.labcord(identity.catalogColorToken))
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(Text("식별색 \(identity.rawValue.suffix(2))"))
                        .accessibilityIdentifier("catalog.timerIdentity.color.\(timer.number)")
                }
                Text("타이머 \(timer.number) · \(timer.duration.formatted(.labcordDuration))")
                    .typography(Typography.calloutSemiBold)
                Text(timer.phase.rawValue)
                    .typography(Typography.footnote)
                    .foregroundStyle(.labcord(.labelSecondary))
            }
            ViewThatFits(in: .horizontal) {
                HStack { timerButtons(timer) }
                VStack(alignment: .leading) { timerButtons(timer) }
            }
            .buttonStyle(.labcord(.secondary, size: .small))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catalog.timerIdentity.timer.\(timer.number)")
    }

    @ViewBuilder
    private func timerButtons(_ timer: CatalogIdentityTimer) -> some View {
        Button(timer.primaryAction.title) {
            session.perform(timer.primaryAction.event, id: timer.id)
        }
        .disabled(timer.phase == .completed)
        .accessibilityIdentifier("catalog.timerIdentity.primary.\(timer.number)")
        Button("종료") { session.perform(.end, id: timer.id) }
            .disabled(!timer.isInProgress)
            .accessibilityIdentifier("catalog.timerIdentity.end.\(timer.number)")
        Button("삭제", role: .destructive) { session.perform(.deleted, id: timer.id) }
            .buttonStyle(.labcord(.quaternary, size: .small))
            .accessibilityIdentifier("catalog.timerIdentity.delete.\(timer.number)")
    }

    private func recordRow(_ record: CatalogIdentityRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("타이머 \(record.timerNumber)")
                .typography(Typography.footnote)
                .foregroundStyle(.labcord(.labelSecondary))
            TimelineItem(
                "타이머 \(record.timerNumber)",
                timestamp: record.recordedAt.formatted(date: .omitted, time: .standard),
                showMemo: false,
                type: .timer
            ) {
                TimerRecord(
                    setDuration: Duration.seconds(record.durationSeconds)
                        .formatted(.labcordDuration),
                    elapsedTime: "\(record.segmentSeconds)초 실행",
                    cumulativeTime: "\(record.cumulativeSeconds)초",
                    pauseCount: "(\(record.pauseCount))",
                    state: record.state,
                    identity: record.identity
                )
            }
        }
    }
}

private struct CatalogIdentityTimer: Identifiable {
    enum Phase: String {
        case ready = "대기"
        case running = "진행 중"
        case paused = "일시정지"
        case completed = "완료"
    }

    let id = UUID()
    let number: Int
    let durationSeconds: Int
    var phase = Phase.ready
    var runningSince: Date?
    var cumulativeSeconds: TimeInterval = 0
    var pauseCount = 0
    var duration: Duration { .seconds(durationSeconds) }
    var isInProgress: Bool { phase == .running || phase == .paused }

    var primaryAction: (title: String, event: LabcordTimerRecordState) {
        switch phase {
        case .ready: ("실행", .start)
        case .running: ("일시정지", .paused)
        case .paused: ("재개", .resume)
        case .completed: ("완료", .end)
        }
    }

    func accepts(_ event: LabcordTimerRecordState) -> Bool {
        switch event {
        case .start: phase == .ready
        case .paused: phase == .running
        case .resume: phase == .paused
        case .end: isInProgress
        case .deleted: true
        }
    }

    mutating func stopSegment(at date: Date) -> Int {
        let segment = runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0
        cumulativeSeconds += segment
        runningSince = nil
        return Int(segment)
    }
}

private struct CatalogIdentityRecord: Identifiable {
    let id = UUID()
    let timerID: UUID
    let timerNumber: Int
    let durationSeconds: Int
    let recordedAt: Date
    let state: LabcordTimerRecordState
    let identity: LabcordTimerIdentity
    let segmentSeconds: Int
    let cumulativeSeconds: Int
    let pauseCount: Int
}

private struct CatalogIdentitySession {
    var timers: [CatalogIdentityTimer] = []
    var records: [CatalogIdentityRecord] = []
    private(set) var identities: [UUID: LabcordTimerIdentity] = [:]
    private var nextIdentity = 0
    private var nextNumber = 1

    mutating func addTimer() {
        let roles = LabcordTimerIdentity.allCases
        let used = timers.filter { $0.phase == .running }.compactMap { identities[$0.id] }
        let candidates = roles.indices.map { (nextIdentity + $0) % roles.count }
        let selected = candidates.first { !used.contains(roles[$0]) } ?? nextIdentity
        let timer = CatalogIdentityTimer(
            number: nextNumber, durationSeconds: 30 * ((nextNumber - 1) % 4 + 1)
        )
        identities[timer.id] = roles[selected]
        nextIdentity = (selected + 1) % roles.count
        nextNumber += 1
        timers.append(timer)
    }

    mutating func perform(_ event: LabcordTimerRecordState, id: UUID, at date: Date = .now) {
        guard let index = timers.firstIndex(where: { $0.id == id }),
              let identity = identities[id], timers[index].accepts(event) else { return }
        var timer = timers[index]
        var segment = 0
        switch event {
        case .start:
            timer.phase = .running
            timer.runningSince = date
        case .paused:
            segment = timer.stopSegment(at: date)
            timer.phase = .paused
            timer.pauseCount += 1
        case .resume:
            timer.phase = .running
            timer.runningSince = date
        case .end:
            segment = timer.stopSegment(at: date)
            timer.phase = .completed
        case .deleted:
            let keepsRecord = timer.isInProgress
            segment = timer.stopSegment(at: date)
            timers.remove(at: index)
            guard keepsRecord else { return }
        }
        records.append(CatalogIdentityRecord(
            timerID: id, timerNumber: timer.number, durationSeconds: timer.durationSeconds,
            recordedAt: date, state: event, identity: identity,
            segmentSeconds: segment, cumulativeSeconds: Int(timer.cumulativeSeconds),
            pauseCount: timer.pauseCount
        ))
        if event != .deleted { timers[index] = timer }
    }
}

private extension LabcordTimerIdentity {
    var catalogColorToken: ColorToken {
        switch self {
        case .identity01: .timerIdentity01
        case .identity02: .timerIdentity02
        case .identity03: .timerIdentity03
        case .identity04: .timerIdentity04
        case .identity05: .timerIdentity05
        }
    }
}

#Preview("타이머 식별색 예제") {
    _ = FontRegistration.register()
    return CatalogTimerIdentityScenario()
        .padding()
}
