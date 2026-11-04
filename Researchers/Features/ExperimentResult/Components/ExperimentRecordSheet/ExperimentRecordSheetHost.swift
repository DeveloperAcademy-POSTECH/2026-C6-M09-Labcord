import AVFoundation
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct ExperimentRecordSheetHost: View {
    let entry: ExperimentResultDetail.TimelineEntry
    @Binding var note: String
    @Binding var isDeleteConfirmationPresented: Bool
    @Binding var saveMessage: String?
    let canSave: Bool
    let onDismiss: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let onConfirmDelete: () -> Void
    let onCancelDelete: () -> Void

    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var fullScreenVideoPlayer: AVPlayer?
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    @GestureState private var isHeaderDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
    }

    var body: some View {
        GeometryReader { geometry in
            let height = contentHeight > 0 && headerHeight > 0
                ? min(contentHeight + headerHeight, geometry.size.height)
                : geometry.size.height

            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !canSave { onDismiss() }
                    }

                VStack(spacing: 0) {
                    RecordBottomSheetHeader(onDismiss: onDismiss)
                        .onGeometryChange(for: CGFloat.self) { headerGeometry in
                            headerGeometry.size.height.rounded(.up)
                        } action: { headerHeight = $0 }

                    ScrollView {
                        ExperimentRecordSheetView(
                            entry: entry,
                            note: $note,
                            canSave: canSave,
                            onDismiss: onDismiss,
                            onSave: onSave,
                            onDelete: onDelete,
                            isVideoFullScreen: fullScreenVideoPlayer != nil,
                            onOpenVideoFullScreen: { fullScreenVideoPlayer = $0 }
                        )
                            .frame(maxWidth: .infinity)
                            .onGeometryChange(for: CGFloat.self) { contentGeometry in
                                contentGeometry.size.height.rounded(.up)
                            } action: { contentHeight = $0 }
                            .alert(
                                "기록을 삭제할까요?",
                                isPresented: $isDeleteConfirmationPresented
                            ) {
                                Button("기록 삭제", role: .destructive, action: onConfirmDelete)
                                Button("취소", role: .cancel, action: onCancelDelete)
                            } message: {
                                Text("삭제한 기록은 복구할 수 없어요.")
                            }
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDisabled(isHeaderDragging || dragOffset > 0)
                    .frame(height: max(0, height - headerHeight))
                }
                .frame(height: height)
                .overlay(alignment: .top) { headerDragArea }
                .clipShape(sheetShape)
                .background(alignment: .top) {
                    sheetShape
                        .fill(Color("General/Background/Grouped/Secondary"))
                        .frame(height: height + geometry.safeAreaInsets.bottom)
                        .allowsHitTesting(false)
                }
                .opacity(contentHeight > 0 && headerHeight > 0 ? 1 : 0)
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
        .background {
            NativeVideoPlayerPresenter(player: fullScreenVideoPlayer) {
                fullScreenVideoPlayer?.play()
                fullScreenVideoPlayer = nil
            }
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        }
        .labcordDismissKeyboardOnTapOutside()
        .presentationBackground(.clear)
        .presentationCornerRadius(0)
        .presentationDragIndicator(.hidden)
        .alert("기록 변경 실패", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("확인") { saveMessage = nil }
        } message: {
            Text(saveMessage ?? "")
        }
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
