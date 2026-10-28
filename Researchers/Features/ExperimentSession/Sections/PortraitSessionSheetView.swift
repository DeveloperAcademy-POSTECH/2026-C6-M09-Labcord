//
//  PortraitSessionSheetView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI

struct PortraitSessionSheetView: View {
    let store: StoreOf<CameraCaptureFeature>
    let timerStore: StoreOf<SessionTimerFeature>
    let compactHeight: CGFloat
    let expandedHeight: CGFloat
    let bottomInset: CGFloat

    @State private var collapseProgress: CGFloat = 0
    @State private var dragStartProgress: CGFloat?

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let collapseDistance = expandedHeight - compactHeight
                guard collapseDistance > 0 else { return }

                if dragStartProgress == nil {
                    dragStartProgress = collapseProgress
                }

                let proposedProgress = (dragStartProgress ?? 0)
                    + value.translation.height / collapseDistance
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    collapseProgress = min(max(proposedProgress, 0), 1)
                }
            }
            .onEnded { value in
                let collapseDistance = expandedHeight - compactHeight
                guard collapseDistance > 0 else { return }

                let projectedProgress = (dragStartProgress ?? collapseProgress)
                    + value.predictedEndTranslation.height / collapseDistance
                dragStartProgress = nil

                withAnimation(.easeOut(duration: 0.24)) {
                    collapseProgress = projectedProgress >= 0.5 ? 1 : 0
                }
            }
    }

    var body: some View {
        let collapseDistance = expandedHeight - compactHeight

        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    store.send(.cameraSwitchRequested)
                } label: {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.body)
                        .frame(width: 40, height: 40)
                }
                .foregroundStyle(.white)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(.black.opacity(0.5))
                .disabled(store.previewConnector == nil || store.isCameraSwitching)

                HStack(spacing: 12) {
                    Button {
                        store.send(.voiceButtonTapped)
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "record.circle")

                            Text("음성 기록")
                        }
                        .frame(maxWidth: .infinity, maxHeight: 76)
                        .background(
                            .black.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)

                    Button {
                        store.send(.photoButtonTapped)
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.viewfinder")

                            Text("장면 캡쳐")
                        }
                        .frame(maxWidth: .infinity, maxHeight: 76)
                        .background(
                            .black.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)

                    Button {
                        store.send(.videoButtonTapped)
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "video.fill")

                            Text("영상 기록")
                        }
                        .frame(maxWidth: .infinity, maxHeight: 76)
                        .background(
                            .black.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            ZStack(alignment: .top) {
                Color.black

                SessionTimerView(store: timerStore)
                    .padding(.horizontal, 16)
                    .padding(.top, 40)

                Rectangle()
                    .fill(.clear)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.white.opacity(0.45))
                            .frame(width: 36, height: 5)
                            .padding(.top, 8)
                    }
                    .gesture(panelDragGesture)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32))
            .frame(height: expandedHeight)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .offset(y: bottomInset + collapseProgress * collapseDistance)
    }
}
