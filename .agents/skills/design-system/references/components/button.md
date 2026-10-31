# Button

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Button/LabcordButtonStyle.swift)

`save`·`isSaving`·`canSave`는 기존 호출부의 액션·상태입니다.

```swift
Button("저장", action: save)
    .buttonStyle(.labcord(.primary, isLoading: isSaving))
    .disabled(isSaving || !canSave)
```

- `isLoading`은 표시 상태입니다. 중복 실행 방지는 호출부의 `.disabled`로 연결합니다.
- 삭제 동작은 `Button(role: .destructive, action: remove)`를 사용합니다. Style이 native role을 해석합니다.
- `size:`를 생략하면 `.controlSize`를 따릅니다. 아이콘과 텍스트 조합은 native `Label`을 전달합니다.
