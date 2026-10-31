import LabcordDesignSystem
import SwiftUI

struct DesignSystemCatalogSheet<Content: View>: View {
    let context: CatalogContext
    @ViewBuilder let content: () -> Content

    @State private var contentHeight: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    @GestureState private var isHeaderDragging = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var headerControlScale: CGFloat = 1

    var body: some View {
        #if os(iOS)
        GeometryReader { geometry in
            let height = contentHeight > 0
                ? min(contentHeight, geometry.size.height)
                : geometry.size.height

            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)

                sheetContent
                    .frame(height: height)
                    .clipShape(sheetShape)
                    .background(alignment: .top) {
                        sheetShape
                            .fill(sheetBackground)
                            .frame(height: height + geometry.safeAreaInsets.bottom)
                            .shadow(
                                color: sheetShadow,
                                radius: effects.shadowMediumRadius,
                                x: 0, y: effects.shadowMediumOffsetY
                            )
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
            .coordinateSpace(name: "catalogSheetDrag")
        }
        .presentationBackground(Color.clear)
        .presentationCornerRadius(0)
        .presentationDragIndicator(.hidden)

        #else
        sheetContent
            .presentationDragIndicator(.hidden)

        #endif
    }

    private var sheetBackground: Color {
        context == .general
            ? Color("General/Background/Grouped/Secondary", bundle: catalogBundle)
            : Color("Experiment/Background/Grouped/Secondary", bundle: catalogBundle)
    }

    private var sheetShadow: Color {
        context == .general
            ? Color("General/Effect/Shadow/Medium/Color", bundle: catalogBundle)
            : Color("Experiment/Effect/Shadow/Medium/Color", bundle: catalogBundle)
    }

    private var effects: EffectTokens {
        EffectTokens(context: context == .general ? .general : .experiment)
    }

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
    }

    private var headerDragArea: some View {
        Color.clear
            .frame(height: 80)
            .contentShape(Rectangle())
            .highPriorityGesture(headerDrag)
            .padding(
                .horizontal,
                max(60, LayoutTokens.spacing16 + 34 * headerControlScale + LayoutTokens.spacing8)
            )
            .accessibilityHidden(true)
    }

    private var headerDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("catalogSheetDrag"))
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
                    dismiss()
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

    private var sheetContent: some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity)
                #if os(iOS)
                .overlay(alignment: .top) { headerDragArea }
                #endif
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height.rounded(.up)
                } action: { height in
                    contentHeight = height
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(
            context == .general
                ? Color("General/Label/Primary", bundle: catalogBundle)
                : Color("Experiment/Label/Primary", bundle: catalogBundle)
        )
        .labcordDismissKeyboardOnTapOutside()
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }
}
