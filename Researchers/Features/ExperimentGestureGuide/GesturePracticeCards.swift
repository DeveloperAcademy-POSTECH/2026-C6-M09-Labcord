import LabcordDesignSystem
import SwiftUI

struct GesturePracticeCards: View {
    let width: CGFloat
    @Binding var page: Int
    let device: GestureDevice
    let completed: Set<PracticeGesture>
    let onManualScroll: () -> Void
    @State private var cardDrag: CGFloat = 0
    @State private var isDragging = false
    @GestureState private var gestureActive = false

    var body: some View {
        let cardWidth = min(width - 76, 326)
        let cardSpacing: CGFloat = 16
        let centeredInset = (width - cardWidth) / 2
        let offset = page == 1
            ? 0 : centeredInset - 16 - CGFloat(page - 1) * (cardWidth + cardSpacing)
        return VStack(spacing: 0) {
            HStack(spacing: cardSpacing) {
                ForEach(PracticeGesture.allCases) { gesture in
                    practiceCard(gesture)
                        .frame(width: cardWidth)
                        .opacity(page == gesture.rawValue ? 1 : 0.6)
                }
            }
            .padding(.leading, 16)
            .offset(x: offset + cardDrag)
            .frame(width: width, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($gestureActive) { _, active, _ in active = true }
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onManualScroll()
                        }
                        cardDrag = value.translation.width
                    }
                    .onEnded { value in
                        isDragging = false
                        let distance = value.predictedEndTranslation.width
                        withAnimation {
                            if abs(distance) > 40 {
                                page = min(max(page + (distance < 0 ? 1 : -1), 1), 3)
                            }
                            cardDrag = 0
                        }
                    }
            )
            .onChange(of: gestureActive) { _, active in
                guard !active, isDragging else { return }
                isDragging = false
                withAnimation { cardDrag = 0 }
            }
            PageControl(pageCount: 3, selection: $page)
        }
    }

    private func practiceCard(_ gesture: PracticeGesture) -> some View {
        HStack(spacing: LayoutTokens.spacing4) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing8) {
                Text(gesture.title)
                    .typography(Typography.bodySemiBold)
                Text(gesture.instruction(for: device))
                    .typography(Typography.subheadline)
            }
            .foregroundStyle(
                Color("Experiment/Fill/White", bundle: LabcordDesignSystemResources.bundle)
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if device == .iPhone && completed.contains(gesture) {
                Image(labcordIcon: .checkBold)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(
                        Color(
                            "Experiment/Brand/Primary",
                            bundle: LabcordDesignSystemResources.bundle
                        )
                    )
                    .accessibilityLabel("인식 완료")
            }
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.vertical, LayoutTokens.spacing12)
        .background(
            Color("Experiment/Fill/Secondary", bundle: LabcordDesignSystemResources.bundle),
            in: RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
        )
        .accessibilityElement(children: .combine)
    }

}
