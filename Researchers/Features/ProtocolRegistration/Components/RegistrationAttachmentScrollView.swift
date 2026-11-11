import LabcordDesignSystem
import SwiftUI

private struct AttachmentScrollMetrics: Equatable {
    var contentWidth: CGFloat = 0
    var visibleWidth: CGFloat = 0
    var offset: CGFloat = 0
}

struct RegistrationAttachmentScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var metrics = AttachmentScrollMetrics()
    @ScaledMetric(relativeTo: .body) private var attachmentHeight: CGFloat = 100

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    content
                }
            }
            .frame(height: attachmentHeight)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: AttachmentScrollMetrics.self) { geometry in
                AttachmentScrollMetrics(
                    contentWidth: geometry.contentSize.width,
                    visibleWidth: geometry.containerSize.width,
                    offset: geometry.contentOffset.x + geometry.contentInsets.leading
                )
            } action: { _, newMetrics in
                metrics = newMetrics
            }

            if metrics.contentWidth > metrics.visibleWidth && metrics.visibleWidth > 0 {
                GeometryReader { geometry in
                    let trackWidth = geometry.size.width
                    let visibleFraction = min(metrics.visibleWidth / metrics.contentWidth, 1)
                    let thumbWidth = trackWidth * visibleFraction
                    let scrollRange = metrics.contentWidth - metrics.visibleWidth
                    let progress = min(max(metrics.offset / scrollRange, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(
                            "General/Separator/Opaque"
                        ))
                        Capsule()
                            .fill(Color(
                                "General/Border/Strong"
                            ))
                            .frame(width: thumbWidth)
                            .offset(x: (trackWidth - thumbWidth) * progress)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
    }
}

#Preview("사진 첨부 스크롤") {
    RegistrationAttachmentScrollView {
        ForEach(0..<10, id: \.self) { index in
            RoundedRectangle(cornerRadius: 8)
                .fill(.gray.opacity(0.15))
                .frame(width: 100, height: 100)
                .overlay { Text("\(index + 1)") }
        }
    }
    .padding(16)
}
