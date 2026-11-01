import SwiftUI

public struct LiveActivityControlButton: View {
    public enum Kind: Sendable {
        case retry
        case audioStop
        case videoStopComplete
        case videoStopInProgress
    }

    private let kind: Kind
    private let progress: Double
    private let action: () -> Void

    public init(kind: Kind, progress: Double = 0, action: @escaping () -> Void) {
        self.kind = kind
        self.progress = progress
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                if kind == .retry || kind == .audioStop {
                    Circle().fill(Color(.General.Brand.subtle).opacity(0.5))
                } else if kind == .videoStopComplete {
                    Circle().strokeBorder(Color(.General.Fill.light), lineWidth: 4)
                } else if kind == .videoStopInProgress {
                    Circle().strokeBorder(Color(.General.Fill.tertiary), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: normalizedProgress)
                        .stroke(
                            Color(.General.Fill.light),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .padding(2)
                        .rotationEffect(.degrees(-90))
                }

                IconArtwork(
                    icon: kind == .retry ? .arrowCounterClockwiseBold : .stop,
                    size: 24
                )
                    .foregroundStyle(
                        kind == .retry || kind == .audioStop
                            ? Color(.General.Brand.primary)
                            : Color(.General.Recording.Active.color)
                    )
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(LabcordPlainButtonStyle())
        .accessibilityLabel(Text(kind == .retry ? "다시 시도" : "기록 중지"))
    }

    private var normalizedProgress: CGFloat {
        guard progress.isFinite else { return 0 }
        return CGFloat(min(max(progress, 0), 1))
    }
}

#Preview("Live Activity Controls") {
    HStack {
        LiveActivityControlButton(kind: .retry) {}
        LiveActivityControlButton(kind: .audioStop) {}
        LiveActivityControlButton(kind: .videoStopComplete) {}
        LiveActivityControlButton(kind: .videoStopInProgress, progress: 0.6) {}
    }
    .padding()
    .background(.black)
}
