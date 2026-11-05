# Gesture Guide Item

안내 문구와 미디어 View를 전달합니다.

```swift
GestureGuideItem(title: "음성 녹음", description: "손을 펼쳤다가 주먹 쥐기",
                 layout: .landscape) { gestureMedia }
```

- `media` 슬롯은 안내용 콘텐츠이며 제스처 감지·카메라 세션을 시작하지 않습니다.
- `.portrait`·`.landscape` 배치는 호출자가 선택합니다. 설명의 SwiftUI 기본 줄바꿈을 고정 높이로 자르지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/GestureGuideItem/GestureGuideItem.swift)
