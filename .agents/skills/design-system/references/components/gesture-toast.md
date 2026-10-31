# Gesture Toast

인식 안내 문구와 뒤따르는 체크 아이콘 여부를 전달합니다.

```swift
GestureToast(title: "음성 녹음", subtitle: "제스처가 인식됐어요",
             showsFollowingIcon: wasRecognized)
```

- 제스처 감지나 자동 사라짐을 수행하지 않습니다. 실제 인식 결과와 표시 수명은 호출부가 갱신합니다.
- `showsFollowingIcon`은 체크 아이콘 표현만 전환하며 별도 완료 상태를 저장하지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Feedback/GestureToast.swift)
