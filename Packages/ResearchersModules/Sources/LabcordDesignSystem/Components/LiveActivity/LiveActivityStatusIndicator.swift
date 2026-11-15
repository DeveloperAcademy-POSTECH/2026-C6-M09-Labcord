import SwiftUI

public struct LiveActivityStatusIndicator: View {
    public enum Status: Sendable {
        case audioSaving
        case audioSaved
        case timerCompleted
        case watchConnected
    }

    private let status: Status
    private let progress: Double
    private let color: Color

    public init(
        status: Status,
        progress: Double = 0,
        color: Color? = nil
    ) {
        self.status = status
        self.progress = progress
        self.color = color ?? Color(.General.Brand.primary)
    }

    public var body: some View {
        ZStack {
            if status == .audioSaving {
                Circle().strokeBorder(Color(.General.Brand.tertiary).opacity(0.5), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: normalizedProgress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .padding(2)
                    .rotationEffect(.degrees(-90))
            } else if status == .audioSaved || status == .timerCompleted {
                Circle().strokeBorder(color, lineWidth: 4)
            }

            IconArtwork(icon: status == .watchConnected ? .watchCheck : .checkBold,
                               size: status == .watchConnected ? 48 : 24)
                .foregroundStyle(color)
        }
        .frame(width: 48, height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var normalizedProgress: CGFloat {
        guard progress.isFinite else { return 0 }
        return CGFloat(min(max(progress, 0), 1))
    }

    private var accessibilityDescription: String {
        switch status {
        case .audioSaving: "음성 저장 중"
        case .audioSaved: "음성 저장 완료"
        case .timerCompleted: "타이머 종료"
        case .watchConnected: "Apple Watch 연결됨"
        }
    }
}

#Preview("Live Activity Status") {
    HStack {
        LiveActivityStatusIndicator(status: .audioSaving, progress: 0.6)
        LiveActivityStatusIndicator(status: .audioSaved)
        LiveActivityStatusIndicator(status: .watchConnected)
    }
    .padding()
    .background(.black)
}
