# Protocol Upload Button

부모가 `uploadState: ProtocolUploadButtonState`와 파일 선택 액션을 전달합니다.

```swift
ProtocolUploadButton("프로토콜", description: "파일을 선택해 주세요",
                     state: uploadState, action: selectFile)
```

- `.default`·`.selected`는 표시 상태이며 선택된 파일 자체를 저장하지 않습니다.
- 파일 가져오기 화면·확장자/용량 검증·업로드는 `selectFile` 호출부가 처리합니다.
- `.disabled` 상태와 부모의 `.disabled(...)`를 존중합니다. 기본 상태는 `.default`입니다.
- 보조 설명이 필요하지 않으면 `showDescription: false`를 전달합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/ProtocolUploadButton/ProtocolUploadButton.swift)
