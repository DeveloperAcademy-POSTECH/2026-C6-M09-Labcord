# 간격·모서리·크기

소스: [LayoutTokens.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/LayoutTokens.swift).

```swift
let layout = LayoutTokens()
VStack(spacing: layout.spacing16) { content }
```

- `spacing*`·`radius*`·`iconDefaultSize` 등의 역할을 사용합니다. 컴포넌트 고유 치수를 같은 숫자의 공통 토큰으로 일괄 치환하지 않습니다.
- 공통 토큰을 바꾸면 해당 값을 쓰는 제어의 좁은 화면·큰 글씨 배치를 함께 확인합니다.
