# iOS Icon Button Style

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/IconButton/IOSIconButtonStyle.swift)

`remove`·`isRemoving`은 호출부 액션·상태입니다.

```swift
Button(role: .destructive, action: remove) {
    Image(labcordIcon: .trash)
}
.buttonStyle(.labcordIcon(.secondary, isLoading: isRemoving))
.disabled(isRemoving)
.accessibilityLabel("기록 삭제")
```

- 아이콘 전용 레이블의 접근성 이름은 호출부에서 지정합니다.
- `isLoading`만으로 액션을 막지 않습니다. `.disabled`를 함께 연결합니다.
- `size:`를 생략하면 `.controlSize`를 사용하며 원형 컨테이너와 아이콘은 Dynamic Type에 맞춰집니다.
- `size: .extraLarge`로 Figma의 XLarge 크기를 사용합니다.

- 기본 색상은 General입니다. 실험 영역에서는 `colorPalette: .experiment`를 지정합니다.
