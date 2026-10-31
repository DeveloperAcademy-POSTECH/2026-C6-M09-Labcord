# Overlay

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Display/LabcordOverlay.swift)

`content`는 덮을 View입니다. 시각적인 dim만 필요하면 입력을 통과시킵니다.

```swift
content.overlay {
    LabcordOverlay(strength: .strong).allowsHitTesting(false)
}
```

- `LabcordOverlay` 자체에는 닫기 액션이 없습니다. 배경 탭 닫기는 presentation을 소유한 호출부에서 연결합니다.
- 상·하단 fade는 `content.overlay { LabcordOverlayFade(edge: .top) }`으로 사용합니다. Fade는 입력을 가로채지 않습니다.
- Fade의 기존 여러 blend layer를 임의의 단일 그라디언트로 바꾸지 않습니다.
