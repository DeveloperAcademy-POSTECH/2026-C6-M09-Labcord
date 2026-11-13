//
//  TitleEditOverlayView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/3/26.
//

import ComposableArchitecture
import Foundation
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct TitleEditOverlayView: View {
    let store: StoreOf<TitleEditOverlayFeature>
    @FocusState private var isTitleFocused: Bool
    @State private var inputTitle: String

    init(store: StoreOf<TitleEditOverlayFeature>) {
        self.store = store
        _inputTitle = State(initialValue: store.title)
    }

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
                    .disabled(store.isSaving)

                    Spacer()

                    Text("실험 제목 수정")
                        .typography(Typography.headline)

                    Spacer()

                    Color.clear
                        .frame(width: 50, height: 50)
                }

                VStack(alignment: .trailing, spacing: LayoutTokens.spacing8) {
                    TextField("", text: $inputTitle)
                        .labcordTextFieldStyle(
                            text: inputTitle,
                            focus: $isTitleFocused
                        )
                        .submitLabel(.done)
                        .disabled(store.isSaving)
                        .onChange(of: inputTitle) { _, updatedTitle in
                            let limitedTitle = String(
                                updatedTitle.prefix(TitleEditOverlayFeature.maximumTitleLength)
                            )
                            if updatedTitle != limitedTitle {
                                inputTitle = limitedTitle
                            }
                            store.send(.titleChanged(limitedTitle))
                        }

                    Text("\(store.title.count)/\(TitleEditOverlayFeature.maximumTitleLength)")
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
                    .disabled(store.isSaving)

                    Button {
                        store.send(.saveTapped)
                    } label: {
                        Text("저장")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.labcord(
                        store.canSave ? .filled : .tertiary,
                        size: .large,
                        isLoading: store.isSaving
                    ))
                    .disabled(!store.canSave || store.isSaving)
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
        .alert("제목을 저장하지 못했어요", isPresented: Binding(
            get: { store.hasSaveFailed },
            set: { if !$0 { store.send(.saveFailureDismissed) } }
        )) {
            Button("재시도") {
                store.send(.saveTapped)
            }
            Button("취소", role: .cancel) {
                store.send(.saveFailureDismissed)
            }
        } message: {
            Text("변경한 제목은 유지했어요. 다시 시도해 주세요.")
        }
    }
}

#Preview {
    TitleEditOverlayView(
        store: Store(initialState: TitleEditOverlayFeature.State(
            experimentID: UUID(),
            originalTitle: "촉매 반응 조건 비교 실험"
        )) {
            TitleEditOverlayFeature()
        }
    )
}
