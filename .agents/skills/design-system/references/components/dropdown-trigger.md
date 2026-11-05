# Dropdown Trigger

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/DropdownTrigger/DropdownTrigger.swift)

`selectedTitle`·`selectAll`은 현재 값과 선택 액션입니다.

```swift
DropdownTrigger(value: selectedTitle, state: .filled, options: [
    DropdownOption(title: "전체 상태", action: selectAll)
])
```

- 선택지 배열을 사용하면 항목 선택 시 메뉴가 닫힌 뒤 액션이 실행됩니다. 바깥 탭과 접근성 닫기 동작도 메뉴를 닫습니다.
- 메뉴 열림 상태를 호출부와 공유하려면 `isPresented: $isPresented`를 전달합니다. 비활성 상태에서는 외부 Binding이 `true`여도 메뉴를 열지 않습니다.
- 임의의 View 콘텐츠가 필요하면 `dismissableContent` 클로저의 닫기 함수를 선택 액션에서 직접 호출합니다. 선택지 배열과 이 클로저는 SwiftUI popover로 표시되므로 native `Menu`와 중첩 메뉴·키보드 탐색 등의 동작이 다를 수 있습니다.
- 기존 인자 없는 ViewBuilder는 native `Menu`를 유지합니다. 이 생성자의 Bool `isPresented`는 표시 입력이며 메뉴 열림 상태를 자동으로 전달하지 않습니다.

```swift
DropdownTrigger(value: selectedTitle, isPresented: $isPresented) { dismiss in
    Button("전체 상태") {
        dismiss()
        selectAll()
    }
}
```
