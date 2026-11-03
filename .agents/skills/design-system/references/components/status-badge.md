# Status Badge

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/StatusBadge/StatusBadge.swift)

`status`는 `StatusBadge.Status`의 `.ready`, `.paused`, `.completed`입니다.
호출 화면의 실험 상태를 이 표현 타입으로 변환해 전달합니다.

```swift
StatusBadge(status: status)
```

- `label:`을 생략하면 상태에 맞는 기본 문구를 사용합니다. 문구를 바꾸면 접근성 레이블에도 반영됩니다.
- 이 컴포넌트는 상태 표시입니다. 상태 전환 액션은 별도의 제어에 연결합니다.
- General의 준비 배지는 현재 컴포넌트 바인딩에 맞춘 색상을 사용합니다. 동명 Foundation 역할과 같다고 가정해 강제 치환하지 않습니다.
