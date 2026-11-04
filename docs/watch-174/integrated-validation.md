# Watch 부모 통합 검증

2026-11-05, 제품 코드 `16ace75` 기준. Intents 통합 양쪽 빌드는 `c4dfc1a`,
후속 준비 권한 수정의 iPhone 빌드는 `16ace75`에서 통과했다. 검증별 기준과 한계를 구분한다.
기존 사용자 소유 `Packages/ResearchersModules/Tests/`는 수정·스테이징하지 않았다.
현재 통합 브랜치의 push·PR은 게시하지 않았다. 선행 코드로 iPhone QA Simulator에 설치·실행했으며
Watch·실기기는 조작하지 않았다.

## 반영한 통합과 결함 수정

실제 오디오 라우팅·기록 stream·Watch bridge·최종 ACK 표시·iPhone 기록 dispatch를 연결했다.
기존 타이머 저장을 재사용하고 완료 항목의 표시 상태만 별도 보관한다.
시작·재개·촬영은 카운트다운 후 실행 직전에 승인 토큰을 받고, 취소한 준비의 늦은 응답은 무시한다.

정적 리뷰에서 확인한 취소 의도 역전, 다른 실험 복구 기록의 선택 차단, stream 종료 후 Effect,
준비 화면 닫기 후 늦은 시작, 원본 없는 촬영 실패 재시도 경로를 보완했다.
통합 뒤에는 사진·영상 저장 실패의 confirm 대기 해제, 취소 snapshot 발행, preview 영상의
반복 stop 즉시 실패 응답, 종료 drain 중 child 취소·재촬영으로 저장을 취소하는 경로도 수정했다.
후속으로 미확정 요청·기록별 저장/취소 의도를 atomic journal에 보관하고, 재실행은 원 요청 ID의
상태 조회부터 수행하도록 연결했다. 실제 저장 ID/type/file 확인과 미디어 결과 journal로 ACK 유실·
늦은 결과를 재조회하며, 저장 실패한 사진·영상은 보관 원본으로 confirm/cancel을 재시도한다.
사진 예약의 전체 action chain에 ID를 전달하고 취소 뒤 늦은 child·촬영 이벤트를 차단한다.
실제 새 전사와 저장 수정본의 충돌은 수정본을 유지한 채 receipt로 안내한다.

사용자의 추가 승인에 따라 세 foreground App Intent·App Shortcut을 구현했다. 앱과 Intent는
하나의 Store 및 화면 버튼의 기존 기록/중지 경로를 공유한다. 가이드 연습은 실제 기록을 만들지 않고,
새 remote 촬영은 최신 running 조회·권한·실행 승인을 거친다. 전면 이탈 후 새 녹음 시작을
막고, 음성 재시도는 대상 기록만 복원해 다른 기록의 review 상태를 다시 발행하지 않는다.
이 항목의 정적 추적·컴파일 결과를 실제 기기 회귀 통과로 해석하지 않는다.

## 결과와 한계

| 계층 | 결과 | 입증한 범위 |
| --- | --- | --- |
| 변경 Swift 78개 strict lint | 통과 | `41ff3c2`부터 `c4dfc1a` 및 후속 준비 권한 수정까지, 0 violations |
| `scripts/watch-174/check.sh` | 통과 | 실제 archive IO·누락/역전/중복/충돌·ACK 유실·복구·보존, 타이머/미디어 계약, review gate 3종 |
| 외부 Watch UI·Intent Runtime XCTest 69개 | 통과 | 기존 reducer 회귀 52개와 실제 공통 Runtime 17개. journal 파일 IO·재시작/취소·최신 조회/lease·오프라인 중지·기록 경로. 네트워크·OS 활성/권한은 대역 |
| 실제 SwiftData 타이머 집중 harness | 통과 | in-memory 모델·Repository/mutation, 완료 표시·닫기·중복·보존·sidecar 실패. media/store singleton은 harness 대역 |
| 원본 없는 녹음 시작 실패 집중 harness | 통과 | 실제 시작 메서드·표시 모델 추출, 5개 시작 조건과 3개 표시 게이트. recorder/archive는 대역 |
| iPhone generic Simulator 전체 빌드 | 통과 | `c4dfc1a`, Xcode 27.1·Swift 6.4, 컴파일·링크. 설치·실행은 아님 |
| 준비 권한 수정 후 iPhone 전체 빌드 | 통과 | `16ace75`, 실제 영향 대상 iPhone 전체 scheme 컴파일·링크 |
| 준비 토큰 권한 집중 검사 | 통과 | 실제 perform/consumeToken 함수·실제 DTO로 14조건. 상태×권한, running 사진 dispatch, 토큰 재사용 거절. OS 권한은 대역 |
| Watch generic Simulator 전체 빌드 | 통과 | `c4dfc1a`, 전체 컴파일·링크. 실제 Watch 실행은 아님 |
| 실제 통합 Watch bundle Intent metadata | 통과 | action 3개·autoShortcuts 3개·parameters 0개, foreground·local 인증 export. OS 실행 검증은 아님 |
| 음성 복구·전면 가드 집중 검사 | 통과 | 실제 archive IO 및 제품 함수 기반 21개 assertion. 대상만 transferring→review, 다른 기록 보존, 무결성/IO 오류·PCM 보존 |
| 전사 충돌·미디어/요청 복구 집중 검사 | 통과 | 실제 제품 함수·journal IO에 대역 경계를 둔 검사. 수정 전사 보존·optional 호환·저장 파일 조회·늦은 terminal/failed 결과·원 ID 재조회 |
| iPhone QA Simulator 설치·실행 | 통과 | 앱 실행·홈 진입, 페어링 통신 검증은 아님 |
| CI | 미실행 | 원격 push·PR 게시하지 않음 |
| 실제 WC 통신·카메라·음성·권한·잠금·재연결 | 미실행 | device_list에 페어링 Watch·실기기 없음 |
| Figma 원문 노드·상태·문구 대조 | 통과 | 원 이슈 section과 개별 frame/TEXT/screenshot 실제 조회, 아래 후속 보완 |
| Watch 전체 화면·큰 글씨·기기별 시각 대조 | 미실행 | 실제 Watch 실행 환경 없음 |
| AssistiveTouch 직접 연결·Shortcuts/Siri 실제 실행 | 미실행 | Intent 구현은 사용자 추가 승인으로 진행. 선택기 직접 노출·배정·OS 실행은 연결 가능한 Watch가 없어 미확인 |

외부 QA·실행 로그는 `/Users/hellosunghyun/Documents/Codex/2026-11-05/qa-watch-integrated/`에 보존한다.
UI harness는 `/Users/hellosunghyun/Documents/Codex/2026-11-05/labcord-watch-issues/watch-ui-review-fixes/`,
타이머 harness는 `/tmp/labcord-watch-timer-storage-qa/`에 있다. 별도 새 앱 테스트 타깃이나
의존성을 제품에 추가하지 않았다. 외부 harness의 별도 의존성 해석은 제품 잠금 버전의 검증이 아니다.

## 이슈 완료 판단

| 이슈 | 현재 상태 | 남은 완료 조건 |
| --- | --- | --- |
| #170 | 화면·시작/재개·닫기·상태 흐름 코드 통합 | Watch 렌더와 Figma 대조·페어링 실행 |
| #171 | 타이머·기록·저장/취소/복구 화면 코드 통합 | 실제 저장 ACK·오류·화면 크기 회귀 |
| #173 | 양쪽 통신·iPhone 시작 정책·기록 실행 연결 | 전면/배경/잠금/미실행·ACK 유실·재연결 실기기 검증 |
| #174 | 타이머·촬영·오디오 보관/전사/복구·세 Intent 코드 통합 | AssistiveTouch 직접 연결·실제 성능·끊김·권한·저장 검증 |
| #169·#172 | 하위 구현·검증 집계 중 | 위 하위의 완료 증거 확보 |

여섯 이슈를 완료 처리하지 않았다. 다음 검증에는 AssistiveTouch를 지원하는 페어링 실기기가
필요하다. 공식 App Shortcuts 기반의 foreground·인증·공통 Store 실행 계약은 구현했고,
OS·기기별 목록 노출, 사용자 단축어 필요 여부, 실행 타깃·잠금·권한을 실기기로 확인한다.
시스템 더블 탭 하나를 세 제스처 매핑 성공으로 대신하지 않는다.

## 남겨 둔 경계

- 최종 ACK 후에도 음성 원본을 자동 삭제하지 않는다. 보관 기간은 미확정이다.
- 사진 RAM·영상 임시 파일의 강제 종료 복구를 완료로 주장하지 않는다.
- 큰 context/갱신 실패와 64개 초기 replay 누락은 재현·수정했다. 앱 수명 내 모든 phase의
  개별 전송 보완과 초기 목록 전체 replay를 검사했으나 실제 WC OS 전송은 확인이 남아 있다.
- 타이머 기록과 표시 sidecar는 별도 저장이다. sidecar 실패 시 완료 타이머가 보일 수 있으며,
  오류를 반환하고 재시도로 닫기를 마친다.
- Watch 음성 중단은 종료 manifest 확보와 복구를 진행한다. 영구 저장 전에는 저장 완료로 표시하지
  않으며, 실험 완료 후에도 기존 기록 confirm/cancel을 허용한다.

## 후속 검증과 Figma 보완

- 실제 Transport 소스에 오류 주입용 WCSession 대역을 연결해 누적 100개 context 실패,
  동일 revision 재시도 누락, 초기 replay 36개 유실을 재현했다. 수정 후 100개 개별 전송·
  replay, outstanding 중복 방지, 개별 과대 기록 격리, terminal 전송 유지 검사를 통과했다.
  실제 bridge `updates` 함수 본문으로 초기 100개 replay도 확인했다.
- 실제 coordinator/transport 소스를 사용하는 별도 harness로 requestStatus 새 ID 응답,
  완료된 실험의 기존 기록 confirm, 중복 confirm 1회 실행, record 결과 재조회, 완료 후 새 촬영
  거절을 확인했다. SDK·연결·저장 client는 대역이고, SwiftData 모델 검사는 실제 in-memory 저장이다.
- Figma 시작 준비 `587:11233`/숫자 `587:11237`, 재개 확인 `593:10119`, 정리
  `593:11027`/확인 `593:11035`, 프로토콜 타이머 `593:10610`와 자유 모드
  `593:10827`을 조회하고 화면 상태를 보완했다. 원문은
  [실험 선택](https://www.figma.com/design/v6cxQ2I6zURWYQaG5pnuBL?node-id=502-12602)과
  [실험 중](https://www.figma.com/design/v6cxQ2I6zURWYQaG5pnuBL?node-id=502-12297)이다.
- 준비 표시의 별도 지속 시간은 Figma에 없으므로 임의로 카운트다운/토큰 TTL을 늘리지 않았다.
  재개는 확인 뒤 승인하고, 정리 화면은 닫은 뒤 늦은 결과로 다시 열리지 않는다.
  완료 안내는 실험 종료만 확인하며 미수신 backlog까지 모두 저장됐다고 주장하지 않는다.
- 프로토콜은 실제 duration의 원형 프리셋을 쓰며 자유 모드의 고정 프리셋 중복 노출을 제거했다.
  승인된 중단 후 저장·끊김 중 녹음 지속 정책은 과거 Figma 문구보다 우선한다.
- iPhone QA Simulator에 앱 설치·실행 후 홈 화면 진입을 확인했다. 이는 페어링 통신·
  잠금·음성·카메라 검증을 대체하지 않는다. `iphone-launch.png`를 외부 QA에 보존했다.
- 빌드 중 디스크 ENOSPC로 실패한 검증은 공간 확보 후 재실행했다. 이번 작업의 임시
  DerivedData 재생성 캐시만 정리했고 소스·원본·로그·Build/Products는 보존했다.
- Watch target 단독 `-target/-sdk` 우회 빌드는 host macro 모듈 SwiftSyntax/SwiftOperators
  해석 실패로 중단했다. 이후 정상 공유 scheme·generic destination으로 전체 빌드를 통과했다.
  실패 로그를 보존하며 이 우회 빌드 실패를 성공으로 기록하지 않는다.
- 최근 정상 scheme 빌드는 `-jobs 2 COMPILER_INDEX_STORE_ENABLE=NO`로 실행했다.
  병렬/인덱스 자원만 제한했으며 SDK·의존성·compiler 검사·배포 기준을 낮추지 않았다.

상세 외부 자료는 `figma-audit.md`, `gesture-support-audit.md`, `record-transport-audit.md`,
`core-checks.log`, `environment-failure.md`, `cache-cleanup*.json`에 있다.
최신 증거는 `intent-runtime-validation.md`, `voice-recovery-validation.md`,
`intent-integrated-metadata-validation.md`, `pending-recovery/validation.md`,
`photo-cancellation-validation.md`, `transcript-conflict-validation.md`에 구분해 기록했다.
과거 core harness 성공을 이후 모든 소스 수정의 재실행 성공으로 확대하지 않는다.

## Watch 백그라운드 녹음 설정

기존 `.record/.measurement`와 활성 오디오 세션에 더해 Watch 앱 Info.plist의
`UIBackgroundModes` 배열에 `audio`가 필요함을
[Apple record 문서](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record)와
[백그라운드 모드 설정](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)에서 확인했다.
기존 iPhone 설정 방식을 따라 custom Info.plist를 생성 plist와 합치고 동기화 그룹의 일반
리소스 복사 대상에서 제외했다. signing·entitlement·배포 대상·워크아웃 세션은 바꾸지 않았다.

- **통과:** plist/project 문법 검사, Debug/Release의 동일 source plist 경로 확인.
- **통과:** Watch generic Simulator 빌드 후 실제 최종 bundle의 `UIBackgroundModes == [audio]`,
  bundle ID·companion ID·마이크 안내·WKApplication 보존 확인.
- **미실행:** Release 전체 빌드, 실기기에서 화면 비활성·전화/알람·연결 끊김 중 녹음 지속.
  Debug 빌드와 설정 확인을 Release 실행이나 OS 수명 보장으로 해석하지 않는다.

근거·미확인 조건은 외부 `watch-background-audio-audit.md`에 기록했다.
