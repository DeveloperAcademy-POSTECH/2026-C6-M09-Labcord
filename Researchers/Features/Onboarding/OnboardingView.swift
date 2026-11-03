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
    
    private var skipRow: some View {
        HStack {
            Spacer()
            Button("건너뛰기") { store.send(.skipTapped) }
                .buttonStyle(IOSButtonStyle(.accent, size: .medium))
                .opacity(store.page == .third ? 0 : 1)
                .disabled(store.page == .third)
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing16) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(titleLines, id: \.self) { Text($0) }
            }
            .typography(Typography.title1Bold)
            .foregroundStyle(Color("General/Label/Primary"))
            
            VStack(alignment: .leading, spacing: 0) {
                ForEach(bodyLines, id: \.self) { Text($0) }
            }
            .typography(Typography.body)
            .foregroundStyle(Color("General/Label/Secondary"))
        }
    }
    
    
    private var card: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay (alignment: .top) {
                Image(cardImageName)
                    .resizable()
                    .aspectRatio(402.0 / 597.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .overlay(alignment: .bottom) {
                PageControl(pageCount: 3, selection: .constant(store.page.rawValue + 1))
                    .frame(height: 32)
                    .padding(.bottom, 8)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusLg, style: .continuous))
            .shadow(
                color: Color("General/Effect/Shadow/Medium/Color"),
                radius: EffectTokens().shadowMediumRadius,
                y: EffectTokens().shadowMediumOffsetY
            )
    }
    
    
    private var footer: some View {
        VStack(spacing: LayoutTokens.spacing16) {
            
            HStack(spacing: LayoutTokens.spacing8) {
                if store.page != .first {
                    Button("이전") { store.send(.previousTapped) }
                        .buttonStyle(IOSButtonStyle(.plain, size: .large))
                }
                Button {
                    store.send(store.page == .third ? .startTapped : .nextTapped)
                } label: {
                    Text(store.page == .third ? "시작" : "다음")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(IOSButtonStyle(.filled, size: .large))
            }
        }
        .background(Color("General/Background/Primary"))
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
        store.page == .first ? "onboarding_protocol2" : "onboarding_result2"
    }
}

#Preview {
    OnboardingView(store: Store(initialState: OnboardingFeature.State()) {
        OnboardingFeature()
    })
}
