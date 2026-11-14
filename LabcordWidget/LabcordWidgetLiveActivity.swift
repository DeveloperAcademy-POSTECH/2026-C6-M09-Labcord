//
//  LabcordWidgetLiveActivity.swift
//  LabcordWidget
//
//  Created by 정홍섭 on 11/14/26.
//

import ActivityKit
import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import SwiftUI
import WidgetKit

struct LabcordWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            VStack {
                Text(context.attributes.experimentTitle)
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            let store = Store(
                initialState: TimerLiveActivityFeature.State(
                    attributes: context.attributes,
                    contentState: context.state
                )
            ) {
                TimerLiveActivityFeature()
            }

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("진행 중")
                        .foregroundStyle(Color("Experiment/Feedback/Warning/Foreground"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerIslandIconView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimerLiveActivityExpandedView(store: store)
                }
            } compactLeading: {
                TimerIslandIconView()
            } compactTrailing: {
                CompactTimerView(timer: context.state)
            } minimal: {
                TimerIslandIconView()
            }
        }
    }
}

private struct CompactTimerView: View {
    let timer: TimerActivityAttributes.ContentState

    private var widthReference: String {
        let hours = timer.durationSeconds / 3600
        let minutes = timer.durationSeconds / 60
        if hours > 0 {
            return String(repeating: "8", count: String(hours).count) + ":88:88"
        }
        return String(repeating: "8", count: String(minutes).count) + ":88"
    }

    var body: some View {
        Text(widthReference)
            .monospacedDigit()
            .hidden()
            .overlay {
                Text(
                    timerInterval:
                        timer.endsAt.addingTimeInterval(
                            -TimeInterval(timer.durationSeconds)
                        )...timer.endsAt,
                    countsDown: true
                )
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .lineLimit(1)
            }
            .frame(minWidth: 30)
            .foregroundStyle(Color("Experiment/Feedback/Warning/Foreground"))
    }
}

private struct TimerLiveActivityExpandedView: View {
    let store: StoreOf<TimerLiveActivityFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("타이머가 진행 중이에요")
                .font(.headline)

            Text(store.experimentTitle)
                .foregroundStyle(.secondary)

            Text(
                timerInterval:
                    store.timer.endsAt.addingTimeInterval(
                        -TimeInterval(store.timer.durationSeconds)
                    )...store.timer.endsAt,
                countsDown: true
            )
            .font(.title2)
            .monospacedDigit()
            .foregroundStyle(Color("Experiment/Feedback/Warning/Foreground"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TimerIslandIconView: View {
    var body: some View {
        Image(labcordIcon: .timer)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(Color("Experiment/Feedback/Warning/Foreground"))
    }
}

private enum TimerLiveActivityPreview {
    static let attributes = TimerActivityAttributes(
        experimentID: UUID(),
        experimentTitle: "촉매 반응 실험"
    )

    static let state = TimerActivityAttributes.ContentState(
        timerID: UUID(),
        endsAt: Date.now.addingTimeInterval(180),
        durationSeconds: 180
    )
}

#Preview("확장형", as: .dynamicIsland(.expanded), using: TimerLiveActivityPreview.attributes) {
    LabcordWidgetLiveActivity()
} contentStates: {
    TimerLiveActivityPreview.state
}

#Preview("축소형", as: .dynamicIsland(.compact), using: TimerLiveActivityPreview.attributes) {
    LabcordWidgetLiveActivity()
} contentStates: {
    TimerLiveActivityPreview.state
}

#Preview("최소형", as: .dynamicIsland(.minimal), using: TimerLiveActivityPreview.attributes) {
    LabcordWidgetLiveActivity()
} contentStates: {
    TimerLiveActivityPreview.state
}
