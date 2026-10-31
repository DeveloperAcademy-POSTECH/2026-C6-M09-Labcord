# Text Field

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/TextField/LabcordTextFieldStyle.swift)

iOS 예제의 `name`은 부모의 문자열 Binding이고 `focus`는 이 화면의 `FocusState<Bool>`입니다.

```swift
TextField("프로토콜 이름", text: $name)
    .labcordTextFieldStyle(text: name, focus: $focus, isError: hasNameError)
    .submitLabel(.done)
    .disabled(isSaving)
```

- 편의 modifier의 `text:`는 현재 `String`입니다. 입력 값과 실제 포커스로 빈 값·입력됨·활성 상태를 계산합니다.
- `.textFieldStyle(.labcord(...))`만 사용하면 표시 플래그와 포커스 연결을 호출부가 관리합니다. 표시용 `isDisabled` 대신 native `.disabled`로 실제 입력도 막습니다.
- 타이틀·필수 표시·피드백은 [Field Container](field-container.md), 여러 입력의 포커스와 바깥 탭 해제는 [입력 포커스](../input-focus.md)를 확인합니다.
