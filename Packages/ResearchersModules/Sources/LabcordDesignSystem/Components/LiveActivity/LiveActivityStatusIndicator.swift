import SwiftUI

public struct LiveActivityStatusIndicator: View {
    public enum Status: Sendable {
        case audioSaving
        case audioSaved
        case watchConnected
    }

    private let status: Status
    private let progress: Double

    public init(status: Status, progress: Double = 0) {
        self.status = status
        self.progress = progress
    }

    public var body: some View {
        ZStack {
            if status == .audioSaving {
                Circle().strokeBorder(Color(.General.Brand.tertiary).opacity(0.5), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: normalizedProgress)
                    .stroke(
                        Color(.General.Brand.primary),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .padding(2)
                    .rotationEffect(.degrees(-90))
            } else if status == .audioSaved {
                Circle().strokeBorder(Color(.General.Brand.primary), lineWidth: 4)
            }

            IconArtwork(icon: status == .watchConnected ? .watchCheck : .checkBold,
                               size: status == .watchConnected ? 48 : 24)
                .foregroundStyle(Color(.General.Brand.primary))
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
