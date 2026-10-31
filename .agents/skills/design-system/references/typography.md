# Typography

소스: [Typography.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/Typography.swift), [TypographyStyle.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/TypographyStyle.swift).

```swift
Text("프로토콜 이름").typography(Typography.bodySemiBold)
```

- 앱 진입점에서 `FontRegistration.register()`를 한 번 호출합니다. 컴포넌트마다 등록하지 않습니다.
- iOS는 Pretendard, Watch는 시스템 글꼴·Dynamic Type을 유지합니다.
- 정확한 기본 행간은 기본 글자 크기에 적용됩니다. 큰 글씨에 고정 높이·강제 줄 수를 추가하지 않습니다.
- 강조는 필요한 `*SemiBold` 등 공개 스타일을 선택하고 호출부의 임의 글꼴 크기로 바꾸지 않습니다.
