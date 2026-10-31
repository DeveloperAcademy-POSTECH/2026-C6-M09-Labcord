# RecordBottomSheet

부모가 presentation, 편집용 `draftTranscript`·`draftMemo` Binding, 저장 가능 여부와 콜백을 제공합니다.
음성 유형은 실제 재생 Binding과 [VoicePlayer](voice-player.md)의 엔진 연결도 필요합니다.

```swift
RecordBottomSheet(type: .voice, contentState: canSave ? .filled : .empty,
                  voiceDuration: durationText, voiceIsPlaying: $isPlaying,
                  voiceProgress: $progress, transcript: $draftTranscript, memo: $draftMemo,
                  onDismiss: closeSheet, onSave: saveDraft, onDelete: deleteRecord)
```

- `.sheet`·`.fullScreenCover` 등으로 표시합니다. draft와 저장값을 분리하고 취소 시 편집값을 버릴지는 부모가 정합니다.
- 바닥 밀착·투명 배경·상단 라운드가 필요하면 호스트가 배치·clipping·presentation 배경을 구성합니다. [카탈로그 호스트](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystemCatalog/DesignSystemCatalog+Sheet.swift)는 참고용이며 제품 의존성으로 가져오지 않습니다.
- `contentState`는 실제 편집·검증 결과로 계산합니다. 기본 빈 콜백·상수 Binding을 실제 저장 기능으로 사용하지 않습니다.
- `onDismiss`를 주면 부모가 presentation을 닫습니다. 저장·삭제 후 저장 처리와 닫힘 순서도 부모가 정합니다.
- 사진·영상은 `photoContent`·`videoContent` 또는 `mediaContent` 슬롯을 사용합니다. 엔진의 시작·중지·자원 정리는 슬롯 호출자가 맡습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Record/RecordBottomSheet.swift) · [콘텐츠 initializer](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Record/RecordBottomSheet+Transcript.swift)
