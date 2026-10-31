import SwiftUI

#if DEBUG
#Preview("기록 바텀 시트 · 타이머") {
    _ = FontRegistration.register()
    return RecordBottomSheet()
        .padding(.top, 20)
        .labcordTheme(LabcordTheme(context: .general))
}

#Preview("기록 바텀 시트 · 음성") {
    _ = FontRegistration.register()
    return RecordBottomSheet(
        type: .voice,
        contentState: .filled,
        transcript: .constant("샘플 B, 반응 시작 5분 후 연한 노란색으로 변했고 침전은 없음"),
        memo: .constant("전사와 메모를 확인했습니다.")
    )
    .padding(.top, 20)
    .labcordTheme(LabcordTheme(context: .general))
}

#Preview("기록 바텀 시트 · 전사 슬롯") {
    _ = FontRegistration.register()
    return RecordBottomSheet(
        type: .voice,
        contentState: .filled,
        transcript: .constant("호출자가 FocusState를 보유한 native 입력 슬롯"),
        memo: .constant("메모")
    ) {
#if os(watchOS)
        Text("호출자 전사 슬롯")
#else
        TextEditor(text: .constant("호출자 전사 슬롯"))
            .labcordTextEditorStyle(
                LabcordTextEditorStyle(
                    placeholder: Text("내용을 입력해 주세요"),
                    isEmpty: false,
                    isFilled: true
                )
            )
#endif
    }
    .padding(.top, 20)
    .labcordTheme(LabcordTheme(context: .general))
}

#Preview("기록 바텀 시트 · 미디어") {
    _ = FontRegistration.register()
    return RecordBottomSheet(
        type: .photo,
        contentState: .filled,
        memo: .constant("반응 후 색 변화를 확인했습니다.")
    ) {
        RoundedRectangle(cornerRadius: 8)
            .fill(.labcord(.fillSecondary))
            .overlay {
                Text("호출자 미디어 슬롯")
                    .typography(Typography.callout)
                    .foregroundStyle(.labcord(.labelSecondary))
            }
    } memoContent: {
        Text("반응 후 색 변화를 확인했습니다.")
            .typography(Typography.subheadline)
            .foregroundStyle(.labcord(.labelPrimary))
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .topLeading)
            .padding()
    }
    .padding(.top, 20)
    .labcordTheme(LabcordTheme(context: .general))
}

#Preview("기록 바텀 시트 · 큰 글자") {
    _ = FontRegistration.register()
    return RecordBottomSheet(
        type: .timer,
        contentState: .filled,
        memo: .constant("긴 메모도 입력 영역 안에서 여러 줄로 표시됩니다.")
    )
    .padding(.top, 20)
    .environment(\.dynamicTypeSize, .accessibility3)
    .labcordTheme(LabcordTheme(context: .experiment))
}
#endif
