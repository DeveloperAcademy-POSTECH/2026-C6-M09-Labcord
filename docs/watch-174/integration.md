# #174 타이머·미디어·Watch 오디오 통합

초기 분리 구현 기준은 `06b5cf2`였다. 현재 `feat/#174-Devin`에서 #173 통신과
#170·#171 화면을 통합했고, 아래 실제 adapter·라우팅을 연결했다.
분리 구현 당시 인계 API와 현재 통합 결과를 구분하며, 실기기 미검증과 Intent는 남아 있다.

## 부모 통합 결과

- 양쪽 기존 WCSession에 오디오 data/file/userInfo 수신과 기록 상태 stream을 연결했다.
  iPhone의 `PhoneWatchAudioService`와 Watch의 `WatchRecordingService`는 앱 수명 동안
  archive·recorder·transfer를 유지한다. 화면 구독 종료가 녹음 취소를 뜻하지 않는다.
- `response.record`도 동일한 record transport로 전달한다. 실험 ID·revision을 확인하고,
  오디오 화면은 이 상태만으로 `.saved`가 되지 않는다. 보관된 전체 manifest와 최종 receipt를
  대조한 뒤 저장 완료를 표시한다.
- 저장 확인·취소는 iPhone 음성 보관 기록이면 실제 receiver로, 사진·영상이면 현재
  Session child로 전달한다. 사진·영상 저장 실패는 별도 confirm 요청에도 실패를 반환하고,
  취소는 `.cancelled` 기록 상태를 발행한다.
- 시작은 **Watch 로컬 3초 카운트다운 → prepareStart → 승인 토큰으로 즉시 start** 순서다.
  재개·사진·영상도 실행 직전 승인받는다. iPhone의 토큰 TTL 3초는 늘리지 않았다.
  닫기·백그라운드·stream 종료·기한 만료는 준비 의도를 무효화한다.
- iPhone의 현재 Session 중단·종료는 사진·영상·음성의 실제 저장 결과와 진행 중 타이머
  저장이 끝난 후 자원을 해제하고 기존 leave/complete 경로로 진행한다. drain 중 child의
  닫기·취소·재촬영은 reducer에서 차단한다. 저장 실패는 원본을 유지하고 실패로 끝낸다.
- Watch 음성은 중단 요청 전에 종료 manifest를 보관하고 전송·확인 상태를 유지한다.
  실험 완료 뒤에도 기존 기록의 confirm/cancel과 타이머 닫기를 허용하여 늦은 정리를 막지 않는다.
- 완료 타이머는 Watch에 남기고 명시적 닫기만 sidecar에 기록한다. iPhone 활성 목록과
  원본 타이머 기록·자연 종료 시각은 유지한다. SwiftData 기록과 sidecar는 별도 저장이며,
  sidecar 실패 시 오류를 반환하고 재시도로 닫기를 끝낸다.
- 녹음 시작 실패는 archive 조회 성공·해당 원본 없음·활성 녹음 없음이 모두 확인된 경우에만
  사용자의 새 녹음을 허용한다. 불명확한 결과나 보관 원본이 있으면 복구를 유지한다.

음성 원본의 자동 삭제·보존 기간은 확정하지 않았다. 사진 RAM·영상 임시 파일의 강제 종료
복구는 완료로 주장하지 않는다. 장기 기록 누적 시 전체 context가 수신 상한을 넘거나
갱신에 실패하면 미확정 상태도 개별
userInfo로 보완한다. outstanding 큐에 같은 snapshot이 있으면 중복 적재하지 않는다.
이 보완은 앱 수명 내 상태 전달이며, 사진·영상의 앱 종료 복구를 새로 보장하지 않는다.

## App Shortcuts와 직접 제스처 검증

2026-11-05 공식 자료와 설치된 WatchOS27.0 SDK를 확인했다.

- [Apple AssistiveTouch 안내](https://support.apple.com/en-ie/guide/watch/apdec70bfd2d/27/watchos/27)는
  사용자 지정 손 제스처와 Siri 단축어 실행을 설명한다.
- [시스템 더블탭](https://developer.apple.com/documentation/watchos-apps/enabling-double-tap)은
  Button/Toggle 하나에 `handGestureShortcut(.primaryAction)`을 지정하는 API다.
  SDK SwiftUI 인터페이스의 `HandGestureShortcut` 공개 값도 `primaryAction` 하나다.
- [고정 PoC README](https://github.com/junghongseop/AppleWatchPoC/blob/6ab92db19b5182b05c9c96af763513b43322b617/README.md)는
  사용자가 단축어를 만들고 AssistiveTouch에 배정하는 절차다.

사용자 생성 단축어 없이 앱 제공 AppShortcut 세 개가 AssistiveTouch 목록에 직접
노출·실행되는지는 확인하지 못했다. 시스템 더블탭 하나를 세 제스처 연결 근거로
대체하지 않는다. 이후 사용자가 공식 App Shortcuts 기반 Intent 구현을 승인하고
직접 AssistiveTouch 연결만 실기기 검증으로 남기도록 선행 조건을 변경했다.
음성 토글·사진 촬영·영상 토글 세 Intent와 AppShortcutsProvider를 구현했다.
모두 전면 실행·기기 인증을 요구하고, 화면과 동일한 WatchIntentRuntime.shared.store를 사용한다.
실제 목록 노출·배정·잠금·기본 탐색 충돌은 페어링 기기로 확인해야 한다.

### App Shortcuts 공식 지원과 남은 확인

[Apple WWDC23 App Shortcuts 세션](https://developer.apple.com/videos/play/wwdc2023/10102/)은
Watch 앱이 제공하는 AppShortcut의 Watch 실행·Shortcuts 앱 노출과 사용자 추가 설정 없는
제공을 설명한다. 따라서 사용자 생성 단축어가 항상 필수라고 단정하지 않는다.
다만 AssistiveTouch 손 제스처 선택기에 이 후보가 직접 나타나는지는 해당 자료로
입증되지 않는다. 이 선택기 확인은 구현 선행 조건이 아니라 남은 실기기 검증이다.

### Intent 실행 계약

파라미터는 없다. 현재 선택을 우선하며 선택이 없을 때 최신 목록의 running 실험이 정확히
하나인 경우에만 snapshot을 확인하고 선택한다. 다른 실험이나 중단 상태를 임의로 재개하지 않는다.
화면·선택이 바뀌면 대기 중 입력을 거절한다. 기록 시작·중지는 기존 recordTapped/stop Action을
사용한다. 미확정 명령·중복 호출·시작/중지/저장 처리 중 입력을 차단한다.
오프라인 음성 보관과 현재 음성의 로컬 중지는 화면과 같은 경로로 유지한다.

기존 제스처 설명 화면에 연습 입력을 연결했다. 연습 버튼과 Intent는 같은 practice Action을
사용하며 실제 녹음·촬영·전송·저장을 하지 않는다. 별도 #152/#176 전체 가이드 구현을 대체하지 않는다.
성공 반환은 앱의 요청 접수이며 수신 ACK·촬영 완료·영구 저장 성공을 뜻하지 않는다.

[AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent)는
채택 시 녹음 동안 Live Activity를 요구한다. 현재 Watch 대상에 새 ActivityKit 구조를 추가하지 않고,
일반 전면 AppIntent가 앱 화면 처리로 넘기는 방식으로 구현했다. AudioRecordingIntent 기반
백그라운드 시작을 지원한다고 주장하지 않는다. 실제 새 녹음 직전과 archive 준비 후에도
OS 전면 상태를 확인하며, 시작한 녹음의 기존 백그라운드 보관은 중단하지 않는다.

## Watch 오디오 실행 설정

전면에서 권한 확인 후 AVAudioSession의 `.record/.measurement`를 활성화하고 기존
AVAudioEngine으로 시작한다. Watch 앱의 `UIBackgroundModes = [audio]`를 명시해
화면 비활성 녹음에 필요한 공개 설정을 제공한다. `WKBackgroundModes`나 워크아웃
세션을 대신 추가하지 않는다. interruption 시 확보한 구간을 보관하고 중단 상태를 전달한다.
실제 화면 비활성·잠금·OS 중단에서의 지속성은 페어링 기기로 검증해야 한다.

## 오디오 계약

`WatchAudioMessage`의 chunk/finish/status를 공통 WC 소유자가 라우팅한다.
PCM16 little-endian mono, sampleRate는 캡처 형식을 기록하며 언어와 무관하다.
녹음 ID·실험 ID·시작 시각·sequence·샘플 범위·SHA256을 검증한다.
종료 manifest의 chunkCount와 totalSamples까지 연속적으로 확보해야 완전 수신이다.
동일 키의 동일 내용은 멱등, 다른 내용·중첩 샘플·종료 범위 밖은 충돌이다.

`WatchAudioArchive`는 각 구간 전체를 원자적으로 기록한 뒤 구간 receipt를 반환한다.
finish가 먼저 와도 누락 구간을 수용하며 재시작 후 디스크에서 상태를 재구성한다.
`savedRecordID`는 원본·전사 저장 성공 뒤에만 기록한다. Watch의
`acknowledgeSaved`는 종료 manifest와 전체 sequence 일치를 재확인한다.
구간 ACK·전송 완료·타임아웃은 최종 저장 성공이나 미실행의 증거가 아니다.
최종 ACK 후에도 원본은 유지한다. 보존 기간·자동 삭제 정책은 확정하지 않았다.

기본 보관 상한 256 MiB는 코드의 방어 상한이며 제품 확정 기준이 아니다.
공간 부족 시 기존 파일을 삭제하지 않고 오류를 반환한다. 데이터·전사 원문을
로그에 출력하지 않는다. 로컬 파일은 첫 잠금 해제 이후 보호 옵션으로 저장한다.
잠금 중 수신/녹음의 실제 동작과 보존 정책은 실기기·팀 확인이 필요하다.

## 검증

순수 복구 검사는 아래 명령으로 별도 테스트 타깃 없이 실행한다.

```sh
swiftc -parse-as-library \
  Packages/ResearchersModules/Sources/LabcordShared/Audio/*.swift \
  scripts/watch-174/ArchiveChecks.swift -o /tmp/labcord-174-archive-checks
/tmp/labcord-174-archive-checks
```

누락·역전·중복·충돌·재기동·ACK 유실·용량 제한·원본 유지·직렬화를 확인한다.
앱 빌드·실제 WC 전송·전사 품질·페어링 기기 검증을 대체하지 않는다.

## Watch 캡처·전송 연결 API

앱 수명에 하나씩 생성하고 UI가 사라진다는 이유로 교체하지 않는다.

```swift
let archive = WatchAudioArchive(
    root: URL.applicationSupportDirectory.appending(path: "WatchAudioOutbox")
)
let recorder = WatchAudioRecorder(archive: archive)
let exchange = WatchAudioImmediateExchange()
let transfer = WatchAudioTransferClient(archive: archive) { message in
    try await exchange.send(message)
}
try await recorder.recoverInterruptedRecordings() // 새 녹음 시작 전, 앱 재시작 복구
transfer.startRecovery()
// start(experimentID:) 이벤트를 소비하고 stop()은 원본 종료·manifest 확보까지 기다린다.
// receipts()를 소비해 구간 수신·review·최종 저장·실패 상태를 UI에 전달한다.
```

`WatchAudioRecorder`는 AVAudioEngine의 Float32 mono 입력을 PCM16으로 복사한다.
오디오 콜백은 디스크·네트워크를 기다리지 않는다. 32개 버퍼를 넘기면 실패로 종료하며
이미 커밋된 구간은 유지한다. 요청한 4096프레임보다 큰 콜백도 오류로 처리한다.
쓰기 소비자는 약 16 KiB 단위로 합쳐 보관한다. 이는 초기 방어 구현값으로 지연·전력
제품 기준이 아니다. 오디오 중단·시작 실패·쓰기 실패를 성공으로 표시하지 않는다.
강제 종료 후에는 보관 완료된 연속 prefix를 interrupted manifest로 복구한다.
OS가 강제 종료한 뒤 녹음이 계속된다고 보장하지 않는다.

공통 WC 소유자는 다음을 연결해야 한다. 이 작업에서는 해당 파일을 수정하지 않았다.

| core 접점 | 필요한 호출 |
| --- | --- |
| iPhone `didReceiveMessageData` | 오디오를 식별해 `receiver.receive(data)` 결과를 reply로 전달. 실패도 실제 오류로 전달 |
| Watch 활성화·재연결 | `transfer.recover()`; 수명 시작/종료에서 startRecovery/stopRecovery |
| iPhone `didReceive file` | metadata의 `labcordAudioChunk == true` 확인 후 콜백 안에서 동기적으로 `WatchAudioReceiver.retainIncomingFile(file.fileURL)` 실행. 반환 전 시스템 임시 파일을 보존한 다음 비동기 `receiver.receiveRetainedFile(copyURL)` |
| iPhone 파일 구간 ACK | 반환 receipt를 JSON으로 인코딩해 `transferUserInfo`의 `labcordAudioReceipt: Data`로 전달 |
| iPhone `didReceiveUserInfo` | `labcordAudioMessage: Data`를 `receiver.receive`로 처리하고 반환 receipt를 `labcordAudioReceipt`로 회신 |
| Watch `didReceiveUserInfo` | `labcordAudioReceipt: Data`를 decode 후 `transfer.receive(receipt)` |
| iPhone 앱 재실행 | receiver를 하나 생성하고 `receiver.recover()` |

즉시 전송은 core가 활성화한 `WCSession.default`를 사용한다. 별도 delegate를
설치하지 않는다. 오류/도달 불가 시 보관 구간의 백그라운드 파일 전송을 최대 2개
등록하고 manifest/status를 user-info로 전송한다. 구간 ACK를 디스크에 기억하므로
백그라운드 전송 완료 후에도 ACK가 없으면 다시 조회·전송하며 파일을 지우지 않는다.
원본 파일 보존과 백그라운드 WC 스케줄링은 별개다. 즉시 전사 지연은 보장하지 않는다.

## iPhone 외부 음성 입력

`WatchAudioReceiver(archive:client:locale:contextualStrings:)`의 client에는 기존
`ExperimentClient`를 전달한다. contextualStrings는 **현재 실험 UUID**로 용어를
조회해야 한다. `loadDetail`은 진입 이력을 추가하므로 참고어 조회에 다시 호출하지
말고 core가 이미 가진 detail/cache를 사용한다. locale 기본값은 `.current`이며
호출자가 지원 locale을 지정할 수 있다. 음성 인식은 지원 언어·권한·가용성에 의존하며
자동 언어 감지를 구현했다고 주장하지 않는다. iPhone 마이크 세션은 바꾸지 않는다.

구간은 즉시 디스크에 확보한 뒤 별도 작업에서 순서대로 Speech 버퍼 요청에 넣는다.
재시작·실패 후에는 보관된 연속 prefix부터 다시 전사하므로 이전 텍스트에 단순 추가하면
안 된다. `transcripts()` 이벤트는 header·generationID·revision·throughSample을
포함한다. 같은 generation에서 최신 revision의 `[0, throughSample)` 임시 표시를
교체하고 다른 실험/녹음 이벤트를 무시한다. generation 변경 시 새 전사 시도로 취급한다.
recognizer의 final은 저장 ACK가 아니다. 기존 영구 기록에는 partial/final을 반영하지
않으며 동일 recordingID의 기존 저장 기록이 있으면 원본 경로와 transcript 존재를 확인하고
ACK만 복구한다. 사용자 편집본을 자동 덮어쓰지 않는다. 재전사 버전 UI/모델은 추가하지 않았다.

전체 구간·종료 manifest와 최종 전사를 확보하면 isReviewing을 전달하고 확인을 기다린다.
Watch UI가 3초 자동 저장을 소유하며 backend에는 별도 3초 타이머가 없다.
`isReviewing` receipt 동안 `transfer.confirm(header)`로 즉시 저장하거나
`transfer.cancel(header)`로 취소한다. 취소는 영속 표식만 남기며 원본을 폐기하지 않는다.
저장 성공이 확인된 기록의 취소는 거부한다. 저장 실패는 receipt.failure에 표시하고
다음 status/복구 요청에서 다시 시도한다. 원본 구간에서 CAF staging 복사본을 만들고
기존 `saveAudio`가 staging을 이동해 저장한다. chunk 원본·수신 복사본은 보존한다.

Speech 서비스가 세션을 조기 종료하거나 지원 locale/네트워크/권한이 없으면 성공으로
처리하지 않고 원본을 보존한다. 장시간 세션 제한·지원 언어·경계 품질·부하·실시간 지연,
Watch 백그라운드 녹음 수명은 실제 기기에서 확인해야 한다.

## #173 타이머·미디어 디스패치

public 계약은 `WatchTimerMutation.prepare(_:timers:at:)`와
`WatchMediaCommandHandler.input(for:activeExperimentID:)`다. 부모에서 app 내부
child Action으로 연결한다. child Feature 자체의 접근 수준은 기존과 동일하다.

| core/부모 접점 | 필요한 연결 |
| --- | --- |
| 타이머 명령 | 활성 화면의 `.timer(.watchCommand(command))` |
| 타이머 처리 결과 | `.timer(.delegate(response))`를 core 요청 수명에 반환 |
| 사진·영상·확인·취소 | `.capture(.watchCommand(command))` |
| 미디어 처리 결과 | `.capture(.delegate(.watchResponse(response)))`를 core에 반환 |
| 중단·종료 전 | `.voice(.stopAndSaveRequested)`, `.capture(.video(.stopAndSaveRequested))`, 사진 대기 취소 |
| 진행 중 Watch 녹음 | Watch에서 `await recorder.stop()` 후 manifest 전송. 불통이면 원본과 pending 상태 유지 |
| 중단/종료 확정 | child의 saved/실패와 pending 상태를 확인한 뒤 화면 종료·카메라 deactivate·실험 상태 저장 |
| 타이머 종료 | complete 시 모든 타이머의 endedAt 저장은 core 소유. 실험 pause는 타이머 pause가 아님 |

디스패치 전 core는 버전·실험 UUID·활성 상태·expectedRevision·requestID 중복/충돌과
실행 유효성을 검증한다. iPhone 음성/미디어 간 배타성도 기존 부모 상태로 검증한다.
타이머 ID는 요청 ID, 촬영 ID는 targetID(없으면 요청 ID)로 고정한다. 저장 성공 이후
완료 응답을 보내며 일반 command completed만으로 최종 저장을 추정하지 않는다.
명령 수신 ACK는 core가 별도로 즉시 보낸다. 3초 타임아웃 후 새 ID로 자동 재실행하지
말고 같은 ID의 요청 상태와 snapshot을 조회한다. 미디어 작업을 수신 ACK 전에
예약해 두었다가 늦게 실행하는 정책은 추가하지 않았다.

타이머는 최대 5개, 초 단위 양수·Int32 범위 입력을 방어 검증한다. Watch의 시·분·초
입력을 seconds로 합치고 프로토콜은 snapshot.protocolTimerSeconds 값을 사용한다.
start는 requestID를 타이머 ID로 사용하고 pause/resume/delete는 targetID를 사용한다.
삭제는 실행 중 타이머도 endedAt을 남기고 컬렉션에서 제외한다. 기존 saveTimer를
거친 뒤 컬렉션을 반영한다. 실패 시 pendingSave를 유지해 재시도한다.
여러 저장 중 일부만 성공할 수 있으므로 core는 실패 응답을 완료로 승격하지 않는다.
최신 snapshot의 타이머 ID·상태·기준 시각으로 Watch 남은 시간을 보정한다.

Watch 사진은 명령 수신 후 5초 촬영 대기, 결과 수신 후 review/canAutoSave를 전달한다.
Watch UI가 3초 뒤 confirmRecord를 보내며 backend 자동 저장은 실행하지 않는다. 촬영 대기 중
취소는 captureDelay를 취소한다. 카메라가 준비되지 않거나 권한이 없으면 실패 응답하며
자동 활성화·늦은 재촬영을 하지 않는다. 사용자가 iPhone을 준비하고 다시 요청한다.
영상은 정상 stopVideoRecording을 추가해 취소·파일 삭제와 분리했다. Watch 영상은
녹화 결과 수신 때 previewing, 실제 playbackFinished 뒤에만 review/canAutoSave를 전달한다.
Watch 저장 대기는 명시적 confirmRecord까지 유지한다. 기존 iPhone
영상의 재생 완료 후 3초 정책은 유지한다. #100의 자동 재생 동작은 변경하지 않았다.
confirmRecord/cancelRecord에는 targetID가 필요하며 저장 진행 중 취소는 거부한다.

중단·종료 저장 실패 시 화면 이탈/기존 close·cancel 경로를 먼저 실행하면 안 된다.
기존 부모의 leave/complete 조율은 이번 소유 범위 밖이라 수정하지 않았다. 따라서
이 연결 전에는 실험 중단·종료 요구를 완료로 표시할 수 없다.

## 완료 판단과 남은 통합

| 요구 | 현재 코드/검증 | 완료 판단 |
| --- | --- | --- |
| 프로토콜·자유 타이머, 여러 타이머 조작 | 기존 컬렉션 재사용, public mutation·child dispatch, 순수 검사 | core·Watch UI 연결/실기기 미완료 |
| 타이머 재연결·실험 pause 중 완료 | 기준 시각 보정 순수 검사 | core snapshot·실기기 미완료 |
| Watch 녹음·실시간 전달·iPhone 전사 | 실제 AVAudioEngine/WC/Speech/기존 saveAudio 구현 | WC 라우팅·권한·실기기 미완료 |
| 끊김·누락·중복·역전·재시작 복구 | 디스크 구간/manifest/ACK, 순수 복구 검사 | core 수명 연결·페어링 검증 미완료 |
| 언어·지연·OS 중단·용량 부족 | locale 매개변수·버퍼 상한·오류·원본 보존 | 다언어/지연/기기 OS 중단 미검증 |
| 사진·영상·경과 시각 | child 실행과 정상 영상 stop, startedAt response | UI·실기기 미완료 |
| 카메라 불가/권한/재요청 | 준비 상태·권한 검증, typed 응답 | 실기기 미검증 |
| 3초 자동 저장·확인·취소·재시도 | 사진 결과·Watch 영상 review·Watch 음성 최종 전사 기준 | 최신 Figma 대조 및 실제 조작 미완료 |
| 중단·종료 후 저장 | stopAndSave API 제공 | 부모 조율 미완료 |
| 저장 ACK·중복·편집 보존 | 기존 저장 ID와 원본 경로 확인, 최종 ACK 별도 | 저장 실패/ACK 유실 실기기 미완료 |
| Intent·AssistiveTouch 세 제스처 | 공식 문서·SDK·고정 PoC 확인, 코드 미작성 | 직접 목록 노출 근거·실기기 필요 |

전체 #174 완료나 #169~174 통합 완료로 표시하지 않는다. 타깃·manifest·SwiftData 모델,
공통 WC/ExperimentClient/Repository, 부모/루트/Watch UI 변경은 하지 않았다.
추가 의존성·새 checkout·branch·push·PR 게시·Simulator 조작도 하지 않았다.

## UI handoff 반영 (2026-11-05 최신 지시)

확인한 UI checkout head는 `2af6396`이며 UI 파일은 수정하지 않았다.
`WatchRecordingUIBridge`는 parent가 아래 실제 API를 adapter한다.

| UI 입력/이벤트 | 실제 #174 연결 |
| --- | --- |
| startVoice(experimentID, recordID) | `recorder.start(experimentID:recordingID:)`, 반환 capture stream 소비 |
| stopVoice | activeRecording의 실험/record ID 일치를 확인하고 `await recorder.stop()` 후 archive의 completeManifest/status 대조 |
| stopForExperiment | `try await recorder.stopForExperiment(experimentID)`; writer 배출·연속 원본과 종료 manifest 확인 뒤 반환 |
| retry/reconcile | `transfer.recover()`와 receipt 재조회. 실패한 동일 녹음을 새 ID로 재캡처하지 않음 |
| 음성 confirmRecord/cancelRecord | core가 `receiver.handleRecordCommand(command)`로 라우팅. confirm은 실제 영구 저장 확인 후 saved record 응답 |
| capture recording 이벤트 | UI capturing. 아직 originalRetained로 간주하지 않음 |
| capture retaining/retained 이벤트 | 실제 디스크 확보 범위가 있으므로 originalRetained=true. manifest.interrupted면 불완전 캡처 안내 |
| transfer.receipts() | transcript의 범위·세대와 isReviewing/failure/savedRecordID를 표시 상태로 변환 |
| photo/video response.record | targetID와 동일한 record ID를 대조. previewing은 review 이벤트가 아님 |

사진·영상 시작의 requestID와 Watch record ID는 다를 수 있다. targetID를 우선해
보관·응답하며 구형 호출은 requestID로 호환한다. 사진은 결과 확보 시, 영상은 실제
iPhone 미리보기 종료 후에만 canAutoSave=true다. 음성은 완전 수신과 최종 전사 후
isReviewing=true다. UI가 이를 받아 3초 뒤 저장을 요청한다. backend의 3초 저장
타이머를 제거했으며 기존 iPhone 단독 촬영의 자동 저장 정책은 유지한다.

parent는 각 기록의 presentation revision을 실제 변경 때만 증가시킨다. 동일한
review receipt를 주기적으로 새 revision으로 발행하면 UI의 3초 카운트다운이
반복 초기화되므로 금지한다. transfer는 동일 receipt의 중복 발행을 억제한다.
저장 ACK는 savedRecordID와 manifest/전체 구간 대조를 통과한 뒤에만 saved로
변환한다. command completed·전사 final·파일 전송 완료는 saved 근거가 아니다.
Watch 캡처 원본은 최종 ACK 이후에도 보존한다.

영상 중지는 watchStopRequest로, review의 저장 확인은 watchReviewRequest로 분리한다.
중지 완료는 영상 결과 확보 시 previewing 응답이며 최종 저장 ACK가 아니다.
이후 confirmRecord가 도착해도 먼저 받은 stopVideo의 처리 결과 ID를 덮어쓰지 않는다.

UI originalRetained에는 실제 원본 보관 위치를 구분한다. Watch 음성 retaining은
영속 구간 확보, iPhone 사진 review는 기존 capturedData 메모리 보관이며 영속 파일
확보를 뜻하지 않는다. 영상 preview는 기존 iPhone 임시 영상 파일이다. 이 시점에
영속 원본이 있다고 표시하지 말고 사진/영상은 저장 ACK 후 영구 원본 확보를 표시한다.
사진 RAM·영상 임시 파일의 앱 강제 종료 후 복구까지 구현했다고 보고하지 않는다.

실험 snapshot에 mode·프로토콜 단계 ID/이름이 없어 core의 additive 메타 확장이
필요하다. 이번 소유 범위에서 snapshot을 임의 변경하지 않았다. deleteTimer는
활성 컬렉션에서 제외하면서 timer 기록을 지우지 않고 timerEndedAt을 남긴다.
이미 자연 완료된 타이머는 Repository가 timer.finishedAt을 우선 보존한다. UI의
완료 확인/스와이프 삭제를 같은 deleteTimer로 보내도 실험 기록 자체를 삭제하지 않는다.

## 재실행과 최신 결과

Watch는 변경 명령을 보내기 전에 원 요청 ID를 atomic journal에 보관하고 재실행 시 상태 조회부터
한다. 조회 wrapper의 queriedRequestID가 원 ID와 일치하지 않는 실패는 원 명령 실패로 취급하지 않는다.
명령 결과와 기록의 저장·취소 의도를 별도 보존하고, 실제 saved/cancelled 기록에서 의도를 정리한다.
취소 실패 후 원 촬영 조회로 돌아가도 취소 의도가 지워져 review 자동 저장이 재개되지 않는다.

사진의 5초 예약은 시도 ID를 전체 Action 경로에 전달한다. 취소 뒤 늦은 child 시작·예약 만료·촬영
Action은 같은 ID와 예약 상태를 확인해야 한다. 예약 수용 시각에서 양쪽 카운트다운을 표시한다.
0초 표시만으로 촬영이나 저장 성공을 선언하지 않는다.

사진·영상 저장 실패는 살아 있는 원본으로 같은 recordID의 confirm/cancel을 다시 요청한다.
영구 저장 결과는 기존 저장소의 실험/recordID/type/파일을 확인한 뒤 재발행하며 새 저장을 중복하지 않는다.
늦은 실패·취소도 기존 iPhone journal에 보관한다. 재실행으로 RAM/temp 접근 경로가 사라진 기록은
원본 복구 성공으로 표시하지 않고 결과 확인 필요로 표시한다. 명시 취소는 메타데이터만 정리하며
알 수 없는 temp 원본을 삭제하지 않는다.

originalRetained는 현재 원본 접근이 확인됐다는 표시다. 사진 RAM·영상 temp는 앱 수명 내 보관이며
강제 종료 복구 보장을 뜻하지 않는다. 음성은 archive 구간·manifest·최종 receipt로 별도 검증한다.
명시 음성 재시도는 해당 기록만 보관/remote review를 다시 반영하여 동일 receipt 중복 억제가
실패 UI의 회복을 막지 않게 한다. 다른 기록의 자동 저장 시계는 재설정하지 않는다.

## 기능별 리뷰 분할

사용자 승인에 따라 기존 #170·#171·#173·#174 아래에 #218~#240, #172 아래에 #241을
공식 하위 이슈로 연결했다. 기능 범위와 선행 의존 관계는 각 하위 이슈에 기록한다.
기존 구현 브랜치는 보존하며 새 공식 번호를 사용한 리뷰 브랜치를 구성한다.
전체 구현의 빌드 결과를 재구성한 모든 중간 head의 성공으로 대신하지 않는다.

진행 중인 실험의 준비 토큰 발급은 사진 촬영과 공유하므로 iPhone 마이크 권한을 요구하지 않는다.
ready·paused 실험의 시작·재개는 기존 마이크 권한 조건을 유지하고, 영상 촬영은
실제 `CameraSession.prepareVideoRecording`에서 마이크 권한을 다시 확인한다.
