# Protocol Photo Item

사진 콘텐츠와 제거 액션 또는 사진 추가 버튼을 표시합니다.

```swift
ProtocolPhotoItem(onRemove: removePhoto, content: {
    photoContent
})
ProtocolPhotoItem(isDisabled: isPhotoLimitReached, onAdd: addPhoto)
```

- 사진 콘텐츠의 이미지 로딩·비율과 접근성 설명은 호출부가 제공합니다.
- 추가 제한과 실제 사진 선택·삭제는 호출부가 관리합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/ProtocolPhotoItem/ProtocolPhotoItem.swift)
