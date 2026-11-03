//
//  TitleEditOverlayView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/3/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct TitleEditOverlayView: View {
    let store: StoreOf<TitleEditOverlayFeature>
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        ZStack {
            Overlay()
                .ignoresSafeArea()

            VStack(spacing: LayoutTokens.spacing16) {
                HStack {
                    Button {
                        store.send(.dismissRequested)
                    } label: {
                        Image(labcordIcon: .x)
                    }
                    .buttonStyle(.labcordIcon(.plain, size: .large))

                    Spacer()

                    Text("실험 제목 수정")
                        .typography(Typography.headline)

                    Spacer()

                    Color.clear
                        .frame(width: 50, height: 50)
                }

                VStack(alignment: .trailing, spacing: LayoutTokens.spacing8) {
                    TextField("", text: Binding(
                        get: { store.title },
                        set: { store.send(.titleChanged($0)) }
                    ))
                        .labcordTextFieldStyle(
                            text: store.title,
                            focus: $isTitleFocused
                        )
                        .submitLabel(.done)

                    Text("\(store.title.count)/60")
                        .typography(Typography.subheadline)
                        .foregroundStyle(Color("General/Label/Tertiary"))
                }

                HStack(spacing: LayoutTokens.spacing12) {
                    Button {
                        store.send(.dismissRequested)
                    } label: {
                        Text("취소")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.labcord(.plain, size: .large))

                    Button {
                        store.send(.saveTapped)
                    } label: {
                        Text("저장")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.labcord(store.canSave ? .filled : .tertiary, size: .large))
                    .disabled(!store.canSave)
                }
            }
            .padding(.all, LayoutTokens.spacing16)
            .background(Color("General/Background/Grouped/Secondary"))
            .cornerRadius(28)
            .padding(.horizontal, LayoutTokens.spacing16)
        }
        .recordEditDiscardAlert(isPresented: Binding(
            get: { store.isDiscardConfirmationPresented },
            set: { if !$0 { store.send(.discardCancelled) } }
        ), onDiscard: {
            store.send(.discardConfirmed)
        }, onCancel: {
            store.send(.discardCancelled)
        })
    }
}

#Preview {
    TitleEditOverlayView(
        store: Store(initialState: TitleEditOverlayFeature.State(
            originalTitle: "촉매 반응 조건 비교 실험"
        )) {
            TitleEditOverlayFeature()
        }
    )
}
