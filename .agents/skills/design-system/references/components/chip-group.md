# Chip Group

`samples`는 안정적인 ID를 가진 `Identifiable` 배열이며 `selectedIDs`는 같은 ID 타입의 집합입니다.

```swift
ChipGroup(samples, selection: $selectedIDs, label: \.title,
                 onRemove: removeSample, onAdd: addSample)
```

- 칩 본문을 눌러 선택을 토글하지 않습니다. 제거 버튼은 해당 ID를 선택 집합에서 제거하고 `onRemove`를 호출합니다.
- `onRemove`는 실제 배열도 갱신해야 합니다. `onAdd`는 추가 액션이며 새 항목은 부모가 배열에 넣습니다.
- 추가 버튼이 필요 없으면 `onAdd`를 생략합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Chip/ChipGroup.swift)

- 조회 전용 목록은 `ChipGroup(items: terms, label: \.value)`처럼 `onRemove`를 생략합니다.
  제거 버튼 없이 같은 칩 스타일을 표시하며, 빈 제거 콜백을 전달하지 않습니다.
- 칩의 원래 너비로 행을 배치하므로 짧은 용어는 행 끝에서 압축하지 않고 다음 행으로 이동합니다.
  목록 전체 너비보다 긴 용어만 줄바꿈하며, 큰 글자에서도 세로 여백을 유지합니다.
  카탈로그의 `Chip Group · 한국어 줄바꿈`에서 한글·한영 괄호·긴 용어와 큰 글자를 확인합니다.
