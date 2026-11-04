import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct ExperimentRecordSheetHost: View {
    let entry: ExperimentResultDetail.TimelineEntry
    let onDismiss: () -> Void

    @State private var contentHeight: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    @GestureState private var isHeaderDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
    }

    var body: some View {
        GeometryReader { geometry in
            let height = contentHeight > 0
                ? min(contentHeight, geometry.size.height)
                : geometry.size.height

            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                ScrollView {
                    ExperimentRecordSheetView(entry: entry, onDismiss: onDismiss)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .top) { headerDragArea }
                        .onGeometryChange(for: CGFloat.self) { contentGeometry in
                            contentGeometry.size.height.rounded(.up)
                        } action: { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(isHeaderDragging || dragOffset > 0)
                .frame(height: height)
                .clipShape(sheetShape)
                .background(alignment: .top) {
                    sheetShape
                        .fill(Color("General/Background/Grouped/Secondary"))
                        .frame(height: height + geometry.safeAreaInsets.bottom)
                        .allowsHitTesting(false)
                }
                .opacity(contentHeight > 0 ? 1 : 0)
                .offset(y: dragOffset)
                .onChange(of: isHeaderDragging) { _, isDragging in
                    if !isDragging, !isDismissing {
                        restoreOffset()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .coordinateSpace(name: "recordSheetDrag")
        }
        .presentationBackground(.clear)
        .presentationCornerRadius(0)
        .presentationDragIndicator(.hidden)
    }

    private var headerDragArea: some View {
        Color.clear
            .frame(height: 44)
            .contentShape(Rectangle())
            .highPriorityGesture(headerDrag)
            .padding(.horizontal, 76)
            .accessibilityHidden(true)
    }

    private var headerDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("recordSheetDrag"))
            .updating($isHeaderDragging) { _, isDragging, transaction in
                isDragging = true
                transaction.animation = nil
            }
            .onChanged { value in
                let translation = value.translation
                guard !isDismissing,
                      dragOffset > 0 || abs(translation.height) > abs(translation.width)
                else { return }

                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragOffset = max(0, translation.height)
                }
            }
            .onEnded { value in
                if value.translation.height > 80,
                   abs(value.translation.width) < value.translation.height {
                    isDismissing = true
                    onDismiss()
                } else {
                    restoreOffset()
                }
            }
    }

    private func restoreOffset() {
        guard dragOffset > 0 else { return }
        withAnimation(reduceMotion ? nil : LabcordMotion.settle.animation) {
            dragOffset = 0
        }
    }
}
