//
//  TitleEditOverlayView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/3/26.
//

import LabcordDesignSystem
import SwiftUI

struct TitleEditOverlayView: View {
    let originalTitle: String
    let onDismiss: () -> Void

    @State private var title: String
    @State private var isDiscardConfirmationPresented = false
    @FocusState private var isTitleFocused: Bool

    init(originalTitle: String, onDismiss: @escaping () -> Void) {
        self.originalTitle = originalTitle
        self.onDismiss = onDismiss
        _title = State(initialValue: originalTitle)
    }

    private var canSave: Bool {
        !title.isEmpty && title != originalTitle
    }

    private func requestDismiss() {
        if title == originalTitle {
            onDismiss()
        } else {
            isDiscardConfirmationPresented = true
        }
    }

    var body: some View {
        ZStack {
            Overlay()
                .ignoresSafeArea()

            VStack(spacing: LayoutTokens.spacing16) {
                HStack {
                    Button(action: requestDismiss) {
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
                    TextField("", text: $title)
                        .labcordTextFieldStyle(
                            text: title,
                            focus: $isTitleFocused
                        )
                        .submitLabel(.done)
                        .onChange(of: title) { _, newValue in
                            title = String(newValue.prefix(60))
                        }

                    Text("\(title.count)/60")
                        .typography(Typography.subheadline)
                        .foregroundStyle(Color("General/Label/Tertiary"))
                }

                HStack(spacing: LayoutTokens.spacing12) {
                    Button(action: requestDismiss) {
                        Text("취소")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.labcord(.plain, size: .large))

                    Button(action: {}) {
                        Text("저장")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.labcord(canSave ? .filled : .tertiary, size: .large))
                    .disabled(!canSave)
                }
            }
            .padding(.all, LayoutTokens.spacing16)
            .background(Color("General/Background/Grouped/Secondary"))
            .cornerRadius(28)
            .padding(.horizontal, LayoutTokens.spacing16)
        }
        .alert("기록 수정을 마칠까요?", isPresented: $isDiscardConfirmationPresented) {
            Button("저장하지 않고 닫기", role: .destructive, action: onDismiss)
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장하지 않고 닫으면 변경한 내용은 저장되지 않아요.")
        }
    }
}

#Preview {
    TitleEditOverlayView(originalTitle: "촉매 반응 조건 비교 실험", onDismiss: {})
}
