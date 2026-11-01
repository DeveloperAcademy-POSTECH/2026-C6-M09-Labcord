import SwiftUI

public struct ProgressRing: View {
    private let value: Double

    @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 160
    @ScaledMetric(relativeTo: .title2) private var lineWidth: CGFloat = 16

    public init(value: Double) {
        self.value = value
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.General.Fill.primary), lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)

            if progress > 0 {
                Image("progress-ring-gradient", bundle: .module)
                    .resizable()
                    .frame(width: diameter + lineWidth, height: diameter + lineWidth)
                    .mask {
                        Circle()
                            .trim(from: 0, to: CGFloat(progress))
                            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .frame(width: diameter, height: diameter)
                            .rotationEffect(.degrees(-90))
                    }
            }

            Text("\(Int((progress * 100).rounded()))%")
                .typography(Typography.title2Bold)
                .foregroundStyle(Color(.General.Label.primary))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("진행률")
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }

    private var progress: Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

#Preview("진행률 링") {
    HStack(spacing: 24) {
        ProgressRing(value: 0)
        ProgressRing(value: 1)
    }
    .padding()
}
