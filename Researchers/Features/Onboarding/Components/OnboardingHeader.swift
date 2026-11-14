//
//  OnboardingHeader.swift
//  Researchers
//
//  Created by lwc0113 on 11/4/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct OnboardingHeader: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(titleText)
            }
            .typography(Typography.title1Bold)
            .foregroundStyle(
                Color("General/Label/Primary", bundle: LabcordDesignSystemResources.bundle)
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(bodyText)
            }
            .typography(Typography.body)
            .foregroundStyle(
                Color("General/Label/Secondary", bundle: LabcordDesignSystemResources.bundle)
            )
        }
    }

    private var titleText: String {
        switch store.page {
        case .first:
            return "프로토콜 하나로,\n실험을 간편하게"
        case .second:
            return "필요한 순간,\n동작으로 빠르게"
        case .third:
            return "실험이 끝나면,\n하나의 기록으로"
        }
    }

    private var bodyText: String {
        switch store.page {
        case .first: return "프로토콜에 있는 타이머와 실험 용어 \n그리고 약어까지 자동으로 찾아줘요."
        case .second: return "iPhone과 Apple Watch의 제스처로,\n음성 녹음 · 사진 촬영 · 영상 녹화를 시작할 수 있어요."
        case .third: return "실험 중 남긴 기록을 모아서,\n시간 순으로 확인하고 수정할 수 있어요."
        }
    }
}
