//
//  ExperimentResultView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/29/26.
//

import ComposableArchitecture
import LabcordiOS
import SwiftUI

struct ExperimentResultView: View {
    let store: StoreOf<ExperimentResultFeature>

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter
    }()

    private func formattedDate(_ date: Date) -> String {
        Self.dateTimeFormatter.string(from: date)
    }

    private func formattedDate(_ date: Date?) -> String {
        date.map(formattedDate) ?? "nil"
    }

    private func formattedDates(_ dates: [Date]) -> String {
        "[" + dates.map(formattedDate).joined(separator: ", ") + "]"
    }

    private var detailText: String {
        guard let detail = store.detail else { return "" }

        var lines = [
            "id: \(detail.id)",
            "title: \(detail.title)",
            "createdAt: \(formattedDate(detail.createdAt))",
            "startedAt: \(formattedDate(detail.startedAt))",
            "endedAt: \(formattedDates(detail.endedAt))",
            "status: \(detail.status)",
            "mode: \(detail.mode)",
            "procedure: \(String(describing: detail.procedure))",
            "pauses.count: \(detail.pauses.count)",
            "records.count: \(detail.records.count)",
        ]

        for (index, pause) in detail.pauses.enumerated() {
            lines.append("pauses[\(index)]: id=\(pause.id), "
                + "pausedAt=\(formattedDate(pause.pausedAt)), "
                + "resumedAt=\(formattedDate(pause.resumedAt))")
        }
        for (index, record) in detail.records.enumerated() {
            lines.append("records[\(index)]:")
            lines.append("  id: \(record.id)")
            lines.append("  type: \(record.type)")
            lines.append("  recordedAt: \(formattedDate(record.recordedAt))")
            lines.append("  note: \(record.note)")
            lines.append("  filePath: \(String(describing: record.filePath))")
            lines.append("  transcript: \(String(describing: record.transcript))")
            lines.append("  timerDurationSeconds: "
                + String(describing: record.timerDurationSeconds))
            lines.append("  timerEndedAt: \(formattedDate(record.timerEndedAt))")
            for (pauseIndex, pause) in record.timerPauses.enumerated() {
                lines.append("  timerPauses[\(pauseIndex)]: id=\(pause.id), "
                    + "pausedAt=\(formattedDate(pause.pausedAt)), "
                    + "resumedAt=\(formattedDate(pause.resumedAt))")
            }
        }
        for (index, entry) in detail.statusHistory.enumerated() {
            lines.append("statusHistory[\(index+1)]: id=\(entry.id), "
                + "status=\(entry.status), date=\(formattedDate(entry.date))")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 20) {
            if store.detail != nil {
                Text("기록 종료 화면")

                ScrollView {
                    Text(detailText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            } else if let loadMessage = store.loadMessage {
                Text(loadMessage)
            } else {
                ExperimentProcessingView()
            }

            Button {
                store.send(.homeTapped)
            } label: {
                Text("홈으로 이동")
            }
        }
        .navigationBarBackButtonHidden()
        .task {
            await store.send(.loadResultDetail).finish()
        }
    }
}

#Preview {
    ExperimentResultView(
        store: Store(
            initialState: ExperimentResultFeature.State(experimentID: UUID())
        ) {
            ExperimentResultFeature()
        }
    )
}
