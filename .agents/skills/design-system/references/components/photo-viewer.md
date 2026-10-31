# Photo Viewer

카탈로그의 사진 뷰어는 native `Image`를 조합한 예시이며 공개 `PhotoViewer` 타입은 없습니다.
iOS에서 부모가 로딩한 `photo: UIImage`를 표시할 때는 다음처럼 구성합니다.

```swift
Image(uiImage: photo)
    .resizable().scaledToFit()
    .accessibilityLabel("기록 사진")
```

로딩·오류·확대 동작과 모달의 열기·닫기는 호출자가 구성합니다. 기록 편집과 결합하려면
[RecordBottomSheet](record-bottom-sheet.md)의 사진 슬롯을 사용합니다. 제품에서 카탈로그 샘플 이미지를 직접 의존하지 않습니다.

[카탈로그 구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystemCatalog/DesignSystemCatalog+ReviewMedia.swift) · [모달 호출 예시](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystemCatalog/DesignSystemCatalog+Review.swift)
