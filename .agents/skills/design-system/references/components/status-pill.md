# Status Pill

현재 안내 메시지를 표시합니다.

```swift
StatusPill(statusMessage)
```

- 자동 저장·남은 시간 같은 동작을 실행하지 않습니다. 실제 상태에 맞춰 부모가 메시지를 갱신합니다.
- 긴 문구의 줄바꿈을 허용하므로 고정 높이로 내용을 자르지 않습니다.
- `showIcon: false`로 확인 아이콘을 숨길 수 있습니다. 기본값은 `true`입니다.

- 색상은 기본 `appearance: .experiment`이며 밝은 배경에서는 `.general`을 선택합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/StatusPill/StatusPill.swift)
