# VoicePlayer

부모의 `isPlaying: Bool`, `progress: Double` Binding과 표시할 `durationText: String`, 엔진 콜백을 연결합니다.

```swift
VoicePlayer(duration: durationText, isPlaying: $isPlaying, progress: $progress,
            onEditingChanged: setEditing, onToggle: togglePlayback, onSeek: seek)
```

- `progress`는 0...1 비율입니다. 엔진의 재생 시각으로 주기 갱신하며 탐색 중에는 자동 갱신과 충돌하지 않게 조율합니다.
- `onToggle`을 주면 호출자가 엔진과 Binding을 함께 갱신합니다. 생략하면 버튼은 Binding만 토글합니다.
- `onSeek`는 탐색 확정 위치를 전달합니다. 화면 종료·비활성화 시 엔진 중지는 호출자가 처리합니다.
- 기본 Slider의 탐색 종료는 `onEditingChanged(false)` 다음 `onSeek` 순서입니다. 최종 seek 전에 엔진 진행률로 Binding을 덮어쓰지 않게 조율합니다.
- `waveform` 슬롯은 파형을 표시하며 같은 Slider로 재생 위치를 탐색합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/VoicePlayer.swift) · [오디오 연결 예시](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystemCatalog/DesignSystemCatalog+ReviewAudio.swift)
