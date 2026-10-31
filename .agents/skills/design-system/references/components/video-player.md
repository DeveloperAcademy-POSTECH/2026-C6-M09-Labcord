# Video Player

공개 별도 래퍼 대신 iOS의 `AVKit.VideoPlayer`를 사용합니다. 부모가 `player: AVPlayer`와 시작·종료 동작을 제공합니다.

```swift
VideoPlayer(player: player)
    .onAppear(perform: startPlayback)
    .onDisappear(perform: stopPlayback)
```

- 카탈로그 영상 모달은 열릴 때 자동·무한 재생합니다. 이 동작을 연결할 때는 호출부가 `AVQueuePlayer`·`AVPlayerLooper`의 수명을 유지합니다.
- 비활성화 시 일시정지하고, 복귀 시 이전에 재생 중이었는지에 따라 재개합니다. 닫을 때 중지·loop 해제·항목 정리를 처리합니다.
- native 재생 제어를 유지합니다. 카탈로그의 로컬 재생 객체를 제품 엔진으로 재사용하지 않습니다.
- 기록 메모 편집과 조합할 때는 [RecordBottomSheet](record-bottom-sheet.md)의 영상 슬롯을 사용합니다.

[카탈로그 native 플레이어·수명 관리](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystemCatalog/DesignSystemCatalog+ReviewMedia.swift)
