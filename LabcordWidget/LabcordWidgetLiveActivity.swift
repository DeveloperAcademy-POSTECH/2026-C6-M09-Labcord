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
            let store = Store(
                initialState: TimerLiveActivityFeature.State(
                    attributes: context.attributes,
                    contentState: context.state
                )
            ) {
                TimerLiveActivityFeature()
            }
            let destination = ExperimentLiveActivityURL.url(
                for: context.attributes.experimentID
            )

            return TimerLiveActivityDetailsView(
                store: store,
                isCompleted: context.isStale || context.state.endsAt <= .now,
                destination: destination
            )
            .padding(.vertical, 16)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(
                Color("Experiment/Feedback/Warning/Foreground")
            )
        } dynamicIsland: { context in
            let store = Store(
                initialState: TimerLiveActivityFeature.State(
                    attributes: context.attributes,
                    contentState: context.state
                )
            ) {
                TimerLiveActivityFeature()
            }
            let isCompleted = context.isStale || context.state.endsAt <= .now
            let destination = ExperimentLiveActivityURL.url(
                for: context.attributes.experimentID
            )

            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    TimerLiveActivityDetailsView(
                        store: store,
                        isCompleted: isCompleted,
                        destination: destination
                    )
                    .offset(y: -10)
                }
            } compactLeading: {
                TimerIslandIconView()
            } compactTrailing: {
                CompactTimerView(timer: context.state, isCompleted: isCompleted)
            } minimal: {
                TimerIslandIconView()
            }
        }
    }
}

private struct TimerLiveActivityDetailsView: View {
    let store: StoreOf<TimerLiveActivityFeature>
    let isCompleted: Bool
    let destination: URL?

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isCompleted ? "완료" : "진행 중")
                        .typography(Typography.footnote)
                        .foregroundStyle(Color("Experiment/Feedback/Warning/Foreground"))

                    VStack(alignment: .leading) {
                        if isCompleted {
                            Text("타이머가 종료됐어요")
                                .typography(Typography.callout)
                                .foregroundStyle(
                                    Color("Experiment/Feedback/Warning/OnStrong")
                                )
                        } else {
                            Text(
                                timerInterval:
                                    store.timer.endsAt.addingTimeInterval(
                                        -TimeInterval(store.timer.durationSeconds)
                                    )...store.timer.endsAt,
                                countsDown: true
                            )
                            .typography(Typography.callout)
                            .monospacedDigit()
                            .foregroundStyle(
                                Color("Experiment/Feedback/Warning/OnStrong")
                            )
                        }

                        Text(store.experimentTitle)
                            .typography(Typography.footnote)
                            .foregroundStyle(Color("General/LiveActivity/Label"))
                    }
                }

                Spacer()

                if isCompleted {
                    LiveActivityStatusIndicator(
                        status: .timerCompleted,
                        color: Color("Experiment/Feedback/Warning/Foreground")
                    )
                } else {
                    Image(labcordIcon: .timer)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(Color("Experiment/Feedback/Warning/Foreground"))
                }
            }

            if let destination {
                Link(destination: destination) {
                    Text("실험으로 돌아가기")
                        .typography(Typography.callout)
                        .foregroundStyle(Color("Experiment/Feedback/Warning/OnStrong"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 41)
                        .background(
                            Color("General/LiveActivity/Secondary"),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }
}

private struct CompactTimerView: View {
    let timer: TimerActivityAttributes.ContentState
    let isCompleted: Bool

    private var widthReference: String {
        let hours = timer.durationSeconds / 3600
        let minutes = timer.durationSeconds / 60
        if hours > 0 {
            return String(repeating: "8", count: String(hours).count) + ":88:88"
        }
        return String(repeating: "8", count: String(minutes).count) + ":88"
    }

    var body: some View {
        Group {
            if isCompleted {
                Text("완료")
            } else {
                Text(widthReference)
                    .hidden()
                    .overlay {
                        Text(
                            timerInterval:
                                timer.endsAt.addingTimeInterval(
                                    -TimeInterval(timer.durationSeconds)
                                )...timer.endsAt,
                            countsDown: true
                        )
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                    }
            }
        }
        .monospacedDigit()
        .frame(minWidth: 30)
        .foregroundStyle(Color("Experiment/Feedback/Warning/Foreground"))
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
        endsAt: Date.now.addingTimeInterval(10),
        durationSeconds: 10
    )

    static let completedState = TimerActivityAttributes.ContentState(
        timerID: UUID(),
        endsAt: Date.now.addingTimeInterval(-1),
        durationSeconds: 10
    )
}

#Preview("잠금 화면", as: .content, using: TimerLiveActivityPreview.attributes) {
    LabcordWidgetLiveActivity()
} contentStates: {
    TimerLiveActivityPreview.state
}

#Preview("잠금 화면 완료", as: .content, using: TimerLiveActivityPreview.attributes) {
    LabcordWidgetLiveActivity()
} contentStates: {
    TimerLiveActivityPreview.completedState
}

#Preview("확장형", as: .dynamicIsland(.expanded), using: TimerLiveActivityPreview.attributes) {
    LabcordWidgetLiveActivity()
} contentStates: {
    TimerLiveActivityPreview.state
}

#Preview("완료", as: .dynamicIsland(.expanded), using: TimerLiveActivityPreview.attributes) {
    LabcordWidgetLiveActivity()
} contentStates: {
    TimerLiveActivityPreview.completedState
}

#Preview("축소형", as: .dynamicIsland(.compact), using: TimerLiveActivityPreview.attributes) {
    LabcordWidgetLiveActivity()
} contentStates: {
    TimerLiveActivityPreview.state
}

#Preview("완료 축소형", as: .dynamicIsland(.compact), using: TimerLiveActivityPreview.attributes) {
    LabcordWidgetLiveActivity()
} contentStates: {
    TimerLiveActivityPreview.completedState
}

#Preview("최소형", as: .dynamicIsland(.minimal), using: TimerLiveActivityPreview.attributes) {
    LabcordWidgetLiveActivity()
} contentStates: {
    TimerLiveActivityPreview.state
}
