# Text Area

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/LabcordTextEditorStyle.swift)

iOS 예제의 `memo`는 부모의 문자열 Binding이고 `focus`는 화면의 `FocusState<Bool>`입니다.

```swift
TextEditor(text: $memo)
    .labcordTextEditorStyle(text: memo, focus: $focus, placeholder: Text("메모"))
    .disabled(isSaving)
    .accessibilityLabel("실험 메모")
```

- 플레이스홀더는 실제 입력값이 아닙니다. 빈 값·활성·오류 표시는 현재 문자열과 포커스로 연결합니다.
- 실제 입력 비활성화는 native `.disabled`로 처리합니다. 전체 박스 노출·바깥 탭 해제는 [입력 포커스](../input-focus.md)를 따릅니다.
