# Toast

메시지와 필요한 액션만 전달하는 initializer를 사용합니다.

```swift
LabcordToast("저장했어요", type: .success, onDismiss: dismissToast)
```

- `onAction`·`onDismiss`를 생략하면 해당 버튼이 표시되지 않습니다. 재시도가 필요하면 `actionTitle`과 `onAction`을 함께 전달합니다.
- 콜백이 실제 재시도와 토스트 제거를 처리합니다. 자동 타임아웃이나 저장 동작은 내장하지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/LabcordToast.swift)
