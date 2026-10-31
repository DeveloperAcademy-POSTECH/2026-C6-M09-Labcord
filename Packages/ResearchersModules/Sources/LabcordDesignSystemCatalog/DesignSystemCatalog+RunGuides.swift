import LabcordDesignSystem
import SwiftUI

struct DesignSystemRunGuidesPage: View {
    let item: CatalogItem

    @State private var duration: Duration = .seconds(30)
    @State private var countdown = CatalogCountdown()
    @State private var countdownDigitCount = 2
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        DesignSystemCatalogPage(title: item.title, context: item.context) {
            switch item {
            case .timePicker: timePickerCard
            case .gestureGuideItem: gestureCard
            case .experimentSidePanel: panelCard
            default: EmptyView()
            }
        }
    }

    private var startTitle: String {
        switch countdown.phase {
        case .running: "일시정지"
        case .paused: "재개"
        case .ready, .completed: "시작"
        }
    }

    private var timePickerCard: some View {
        DesignSystemCatalogCard("Time Picker", description: "00부터 시작하는 시·분·초 휠 · 0초에서는 시작 비활성화") {
            TimePicker(duration: $duration)
                .disabled(countdown.isRunning)
                .accessibilityIdentifier("catalog.timePicker")
            Button(startTitle, action: toggleTimer)
                .buttonStyle(.labcord(.primary))
                .disabled(duration <= .zero && !countdown.isRunning)
                .accessibilityIdentifier("catalog.timePicker.start")
            if countdown.hasStarted {
                Button("초기화") { countdown.reset(duration: duration) }
                    .buttonStyle(.labcord(.secondary, size: .small))
                    .accessibilityIdentifier("catalog.timePicker.reset")
            }
            timerStatus
                .typography(Typography.footnote)
                .foregroundStyle(.labcord(.labelSecondary))
        }
        .task(id: countdown.isRunning && scenePhase == .active) {
            guard countdown.isRunning, scenePhase == .active else { return }
            await countdown.run()
        }
        .onChange(of: duration) { _, _ in
            guard !countdown.isRunning else { return }
            countdown.reset(duration: duration)
            countdownDigitCount = String(countdown.remainingSeconds).count
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { countdown.refresh() }
        }
    }

    private func toggleTimer() {
        switch countdown.phase {
        case .running: countdown.pause()
        case .paused: countdown.start()
        case .ready, .completed:
            countdown.reset(duration: duration)
            countdownDigitCount = String(countdown.remainingSeconds).count
            countdown.start()
        }
    }

    @ViewBuilder
    private var timerStatus: some View {
        if countdown.hasStarted {
            CatalogCountdownStatus(
                remainingSeconds: countdown.remainingSeconds,
                digitCount: countdownDigitCount
            )
            .accessibilityIdentifier("catalog.timePicker.remaining")
        } else {
            Text("시간을 선택해 주세요")
        }
    }

    private var gestureCard: some View {
        DesignSystemCatalogCard("Gesture Guide Item", description: "제스처 이미지와 두 가지 배치") {
            CatalogRunGestureScenario()
        }
    }

    private var panelCard: some View {
        DesignSystemCatalogCard("Experiment Side Panel", description: "정렬 방향을 유지하며 펼치거나 접기") {
            CatalogRunSidePanelScenario()
        }
    }
}

#Preview("실험 진행 안내 카탈로그") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemRunGuidesPage(item: .gestureGuideItem)
    }
}
