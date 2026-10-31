# Dropdown Trigger

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/DropdownTrigger/DropdownTrigger.swift)

`selectedTitle`·`selectAll`은 현재 값과 선택 액션입니다.

```swift
LabcordDropdownTrigger(value: selectedTitle, state: .filled) {
    Button("전체 상태", action: selectAll)
}
```

- iOS에서는 native `Menu`를 사용합니다. 메뉴의 각 액션에서 값과 도메인 선택 상태를 갱신합니다.
- `state`·`isPresented`는 표시 입력이며 메뉴 열림 상태를 돌려주는 Binding이 아닙니다.
- 자체 presentation을 연결할 때는 `LabcordDropdownTriggerLabel`을 레이블로 사용합니다.
