# Record Button

기록 종류와 실제 기록 액션을 연결합니다.

```swift
RecordButton(type: .capture, state: recordState, action: captureFrame)
```

- `.audio`·`.capture`·`.video`는 버튼 종류입니다. 촬영·녹음·영상 저장은 호출부가 실행합니다.
- `.disabled`와 부모의 `.disabled(...)`를 유지합니다.
- 캡처 그림은 공용 아이콘과 다른 전용 자산입니다. 아이콘 정리 시 공용 capture로 대체하지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/RecordButton.swift)
