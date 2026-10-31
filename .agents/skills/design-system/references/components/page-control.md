# Page Control

정수 선택은 1부터 시작합니다. 현재 페이지의 부모 Binding을 전달합니다.

```swift
PageControl(pageCount: pageCount, selection: $page)
```

- 모델 값으로 선택한다면 `PageControl(pages: pages, selection: $selectedPage)`를 사용합니다. 원소는 `Hashable`이어야 합니다.
- 범위를 벗어나거나 모델 배열에 없는 값은 선택 없음으로 표시합니다. 페이지 변경 시 부모가 유효한 선택을 유지합니다.
- 페이지 수·선택에 따라 높이와 점 크기가 바뀌므로 호출부에서 고정 높이를 덮어쓰지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Display/PageControl.swift)
