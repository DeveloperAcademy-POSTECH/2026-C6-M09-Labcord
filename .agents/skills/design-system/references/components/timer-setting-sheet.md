# Timer Setting Sheet

저장값을 복사한 `draftDuration: Duration` Binding을 native presentation의 콘텐츠로 전달합니다.

```swift
TimerSettingSheet(duration: $draftDuration, onCancel: cancelDraft,
                  onDelete: deleteTimer, onConfirm: saveDraft)
```

- 휠에서 시간은 `0...23`, 분·초는 `0...59`를 선택합니다. 전달받은 Duration은 자동으로 범위에 맞춰지지 않으므로 호출부에서 검증합니다. 저장·삭제 콜백에서 실제 모델 변경과 presentation 종료를 처리합니다.
- `onCancel`을 제공하면 닫기도 콜백이 맡습니다. 생략하면 native dismiss만 수행하며 Binding 값을 되돌리지 않습니다.
- 휠만 필요하면 [Time Picker](time-picker.md)를 사용합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Timer/TimerSettingSheet.swift)
