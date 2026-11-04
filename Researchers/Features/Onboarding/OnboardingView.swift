//
//  OnboardingView.swift
//  Researchers
//
//  Created by lwc0113 on 11/2/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var store = Store(initialState: OnboardingFeature.State()) {
        OnboardingFeature()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OnboardingBackground(showsLabImage: store.page == .second)

            VStack(alignment: .leading, spacing: 0) {
                skipRow
                header
                    .padding(.top, 19)

                if store.page != .second {
                    OnboardingCard(imageName: cardImageName, currentPage: store.page.rawValue + 1)
                        .padding(.top, LayoutTokens.spacing24)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, LayoutTokens.spacing16)
            .padding(.top, 19)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
        }
    }


    private var skipRow: some View {
        HStack {
            Spacer()
            Button("건너뛰기") {
                store.send(.skipTapped)
                onFinish()
            }
                .buttonStyle(IOSButtonStyle(.accent, size: .medium))
                .opacity(store.page == .third ? 0 : 1)
                .disabled(store.page == .third)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(titleText)
            }
            .typography(Typography.title1Bold)
            .foregroundStyle(Color("General/Label/Primary"))

            VStack(alignment: .leading, spacing: 0) {
                Text(bodyText)
            }
            .typography(Typography.body)
            .foregroundStyle(Color("General/Label/Secondary"))
        }
    }


    private var footer: some View {
        VStack(spacing: LayoutTokens.spacing16) {
            HStack(spacing: LayoutTokens.spacing8) {
                if store.page != .first {
                    Button("이전") { store.send(.previousTapped) }
                        .buttonStyle(IOSButtonStyle(.plain, size: .large))
                        .frame(width: 100)
                }
                Button {
                    if store.page == .third {
                        store.send(.startTapped)
                        onFinish()
                    } else {
                        store.send(.nextTapped)
                    }
                } label: {
                    Text(store.page == .third ? "시작" : "다음")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(IOSButtonStyle(.filled, size: .large))
            }
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.top, LayoutTokens.spacing16)
        .frame(maxWidth: .infinity)
        .background {
            if store.page != .second {
                Color("General/Background/Primary")
                    .ignoresSafeArea(edges: .bottom)
            }
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

    private var cardImageName: String {
        store.page == .first ? "onboarding_protocol2" : "onboarding_result2"
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
