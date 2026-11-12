//
//  ExperimentGestureGuideView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/5/26.
//

import LabcordDesignSystem
import SwiftUI

private struct GestureGuide: Identifiable {
    let imageName: String
    let title: String
    let description: String

    var id: String { imageName }
}

struct ExperimentGestureGuideView: View {
    @State private var selectedGestureTab: TimerTabs.Selection = .set

    let onClose: () -> Void

    private var selectedGestures: [GestureGuide] {
        switch selectedGestureTab {
        case .set: iPhoneGestures
        case .running: appleWatchGestures
        }
    }

    private let iPhoneGestures = [
        GestureGuide(
            imageName: "gesture_iphone_audio",
            title: "음성 녹음",
            description: "손가락 한 개 펴기"
        ),
        GestureGuide(
            imageName: "gesture_iphone_photo",
            title: "사진 촬영",
            description: "손을 폈다가 주먹 쥐기"
        ),
        GestureGuide(
            imageName: "gesture_iphone_video",
            title: "영상 녹화",
            description: "손가락 세 개 펴기"
        )
    ]

    private let appleWatchGestures = [
        GestureGuide(
            imageName: "gesture_watch_audio",
            title: "음성 녹음",
            description: "엄지와 검지를 빠르게 두 번 탭 하기"
        ),
        GestureGuide(
            imageName: "gesture_watch_photo",
            title: "사진 촬영",
            description: "주먹 한 번 쥐기"
        ),
        GestureGuide(
            imageName: "gesture_watch_video",
            title: "영상 녹화",
            description: "주먹 빠르게 두 번 쥐기"
        )
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color("Experiment/Overlay/Scrim")
                .background(
                    VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                )
                .ignoresSafeArea()

            GeometryReader { geometry in
                let isCompactHeight = geometry.size.height < 700

                VStack(spacing: 0) {
                    NavigationPageTitle(
                        "실험 기록",
                        foregroundColor: Color("Experiment/Label/Primary"),
                        onBack: onClose
                    )

                    VStack(spacing: 0) {
                        Text("제스처로 음성 녹음, 사진, 영상을\n빠르게 기록하세요")
                            .padding(.top, isCompactHeight ? 20 : 55)
                            .padding(.bottom, isCompactHeight ? 24 : 57)
                            .multilineTextAlignment(.center)
                            .typography(Typography.body)
                            .foregroundStyle(Color("Experiment/Label/Primary"))

                        VStack(alignment: .center, spacing: 20) {
                            TimerTabs(
                                selection: $selectedGestureTab,
                                style: .pill,
                                leftTitle: "iPhone 제스처",
                                rightTitle: "Apple Watch 제스처"
                            )

                            VStack(alignment: .center, spacing: 12) {
                                ForEach(selectedGestures) { gesture in
                                    GestureGuideItem(
                                        title: gesture.title,
                                        description: gesture.description
                                    ) {
                                        Image(gesture.imageName)
                                            .resizable()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                }
                .padding(.top, 16)
            }
        }
    }
}

#Preview {
    ExperimentGestureGuideView {}
}
