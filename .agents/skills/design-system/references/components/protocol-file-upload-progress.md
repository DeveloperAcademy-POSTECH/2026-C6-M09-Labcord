# Protocol File Upload Progress

파일 이름·형식과 업로드 중 표시를 제공하고 취소 액션을 연결합니다.

```swift
ProtocolFileItemUploadProgress(filename: filename, kind: .pdf, onCancel: cancelUpload)
```

- `kind`는 `FileTypeIcon.Kind`입니다. 표시기는 진행률 수치가 없는 업로드 중 상태입니다.
- `showProgressIndicator: false`는 업로드 표시기를 숨깁니다. 기본값은 `true`입니다.
- 실제 업로드·취소와 파일 상태는 호출부가 소유합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/ProtocolFileItemUploadProgress/ProtocolFileItemUploadProgress.swift)
