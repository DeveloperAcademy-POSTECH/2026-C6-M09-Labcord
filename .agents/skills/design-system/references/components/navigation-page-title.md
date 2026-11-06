# Navigation Page Title

페이지 제목과 선택적인 뒤로 가기 동작을 표시합니다.

```swift
NavigationPageTitle("실험 등록", onBack: goBack)
```

- 기본 색상은 General입니다. 실험 영역에서는 `appearance: .experiment`를 지정합니다.
- `foregroundColor`를 주면 제목과 뒤로 가기 아이콘이 그 색을 사용합니다. 생략하면 appearance 색상을 사용합니다.
- `showsTitle: false`는 제목을 숨깁니다. 기본값은 `true`입니다.
- `onBack`을 생략하면 뒤로 가기 버튼이 표시되지 않습니다. 실제 화면 전환은 호출부가 처리합니다.
- 기존 `NavigationStack`의 내비게이션 막대와 함께 사용할 때 중복 표시 여부를 호출부에서 결정합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/NavigationPageTitle/NavigationPageTitle.swift)
