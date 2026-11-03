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
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        // 위쪽: 건너뛰기 → 제목 → 카드(남은 높이를 모두 사용)
        // 아래쪽: 점 → 버튼 (안전 영역 안, 홈 인디케이터 위에 붙음)
        // 배경은 .background로 둬서 레이아웃 크기에 영향을 주지 않음
        VStack(alignment: .leading, spacing: 0) {
            skipRow
            header
                .padding(.top, 19)

            if store.page != .second {
                card
                    .padding(.top, LayoutTokens.spacing24)
            } else {
                Spacer(minLength: 0)
            }

            footer
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.top, 19)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            background
        }
    }

    // MARK: - 배경

    // 1, 3번은 흰색, 2번은 아래쪽 사진 (사진 높이는 가로 폭의 비율로 정해짐)
    private var background: some View {
        Color("General/Background/Primary")
            .overlay(alignment: .bottom) {
                if store.page == .second {
                    Image("onboarding_lab")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1206 / 1755, contentMode: .fit)
                        .clipped()
                }
            }
            .ignoresSafeArea()
    }

    // MARK: - 위쪽 내용

    // 1, 2번에만 "건너뛰기". 3번에서도 같은 높이를 차지해서 제목 위치가 페이지마다 같게 함
    private var skipRow: some View {
        HStack {
            Spacer()
            Button("건너뛰기") { store.send(.skipTapped) }
                .buttonStyle(IOSButtonStyle(.accent, size: .medium))
                .opacity(store.page == .third ? 0 : 1)
                .disabled(store.page == .third)
        }
    }

    // 제목 두 줄 + 설명 두 줄 (Title1/Emphasized, Body)
    private var header: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing16) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(titleLines, id: \.self) { Text($0) }
            }
            .typography(Typography.title1Bold)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(bodyLines, id: \.self) { Text($0) }
            }
            .typography(Typography.body)
            .foregroundStyle(Color("General/Label/Secondary"))
        }
    }

    // 1, 3번 카드: 가로는 화면 여백을 뺀 전체, 세로는 남은 높이를 모두 사용하고 넘치는 부분은 잘림
    private var card: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Image(cardImageName)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusLg, style: .continuous))
            .shadow(
                color: Color("General/Effect/Shadow/Medium/Color"),
                radius: EffectTokens().shadowMediumRadius,
                y: EffectTokens().shadowMediumOffsetY
            )
    }

    // MARK: - 아래 내용

    // 점 + 버튼 줄. 점은 표시만 하고, 이동은 버튼으로만 함
    private var footer: some View {
        VStack(spacing: LayoutTokens.spacing16) {
            PageControl(pageCount: 3, selection: .constant(store.page.rawValue + 1))

            HStack(spacing: LayoutTokens.spacing8) {
                if store.page != .first {
                    Button("이전") { store.send(.previousTapped) }
                        .buttonStyle(IOSButtonStyle(.plain, size: .large))
                }
                Button {
                    store.send(store.page == .third ? .startTapped : .nextTapped)
                } label: {
                    // 글자를 가로 전체로 늘려야 버튼 배경도 같이 늘어남
                    Text(store.page == .third ? "시작" : "다음")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(IOSButtonStyle(.filled, size: .large))
            }
        }
    }


    private var titleLines: [String] {
        switch store.page {
        case .first: return ["프로토콜 하나로,", "실험을 간편하게"]
        case .second: return ["필요한 순간,", "동작으로 빠르게"]
        case .third: return ["실험이 끝나면,", "하나의 기록으로"]
        }
    }

    private var bodyLines: [String] {
        switch store.page {
        case .first: return ["프로토콜에 있는 타이머와 실험 용어", "그리고 약어까지 자동으로 찾아줘요."]
        case .second: return ["iPhone과 Apple Watch의 제스처로", "음성 녹음 · 사진 촬영 · 영상 녹화를 시작할 수 있어요."]
        case .third: return ["실험 중 남긴 기록을 모아서", "시간 순으로 확인하고 수정할 수 있어요."]
        }
    }

    private var cardImageName: String {
        store.page == .first ? "onboarding_protocol" : "onboarding_result"
    }
}

#Preview {
    OnboardingView(store: Store(initialState: OnboardingFeature.State()) {
        OnboardingFeature()
    })
}
