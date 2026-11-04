# Watch 기능 구현·검증 기록

## 현재 통합 상태

2026-11-05 부모 통합은 `feat/#174-Devin`에서 진행한다. #173 통신과 #170·#171 화면,
#174 기록 bridge·라우팅은 연결했다. 최신 범위·검증·미완료 조건은
[부모 통합 검증](watch-174/integrated-validation.md)을 기준으로 확인한다.
아래 분리 수신 단계의 HEAD·미연결 설명은 당시 기록이며 현재 미구현 목록이 아니다.
원격 push·PR 게시와 이슈 완료 처리는 아직 하지 않았다.

## 분리 구현 당시 기준과 브랜치

- 선행 기준: #216의 `41ff3c2`. #206 → #217 → #216의 `develop` 머지는 아직 완료되지 않았습니다.
- 기능: `feat/#173-Devin`에서 실험 제어·통신 계약을 구현합니다.
- 화면 #170·#171과 기록 #174는 별도 변경으로 유지하고, 최종 PR 준비 시 선행 변경과 Watch 고유 diff를 대조합니다.
- 기존 미추적 테스트·타 담당 변경은 이 작업에 포함하지 않습니다. 아직 push·PR 게시하지 않았습니다.

## 메시지 계약

`LabcordShared/Messages/WatchExperiment*`는 실험 목록·snapshot·명령·처리 결과의 Codable 형식입니다.

- `requestID`는 개별 동작, `experimentID`는 대상 실험, `targetID`는 타이머·기록 또는 조회할 요청을 식별합니다.
- `expectedRevision`은 대상 실험 상태와 비교합니다. 다른 실험의 revision을 비교하지 않습니다.
- `received`는 수신 확인, `processing`은 처리 중, `completed`는 명령 처리 완료입니다. `completed`만으로 미디어 영구 저장 완료를 뜻하지 않습니다. 기록 저장 결과는 #174의 최종 ACK 경로에서 별도로 확인합니다.
- `prepareStart`와 `startToken`은 늦은 시작을 제어할 준비/확정 경로입니다. 토큰 검증·만료와 ACK 유실 조회는 iPhone 처리 구현에서 검증하며, 형식 정의만으로 늦은 실행 방지가 입증되지 않습니다.
- snapshot의 타이머는 iPhone 측정 시각과 남은 시간으로 로컬 표시를 계산하며, 일시정지 값은 흐른 시간만으로 줄이지 않습니다. 기기 시계 차이는 실기기에서 확인해야 합니다.

공통 계약은 실제 소비 경로와 함께 검증하며, 기존 배터리·기기명 메시지는 유지합니다.

## 결정·검증 경계

사용자의 “do best” 지시에 따라 iPhone 전면은 진행 화면 이동, 백그라운드는 저장 후 다음 활성화 시 반영, 다른 실험·편집 충돌은 자동 전환 없이 안내하는 보수적인 방향을 적용합니다. 보호 데이터 접근 실패와 OS 전달 불가는 실패/확인 필요로 처리하며 앱 기동·전면화를 보장하지 않습니다.

제스처는 처음에 연결 확인을 선행했으나, 사용자가 공식 App Shortcuts 기반 구현을 승인하고 직접 연결만 실기기 검증으로 남기도록 변경했습니다. 세 전면 Intent와 공통 실행 Runtime을 구현했습니다. Watch App Shortcut 노출과 AssistiveTouch 설정 목록 노출을 구분합니다. 미검증 상태에서 사용자 단축어 생성 필수 또는 세 제스처 직접 배정 가능이라고 확정하지 않습니다.

## 확인 결과

- 메시지 3파일 SwiftLint strict: 통과.
- 독립 Swift 실행: 명령 ID·토큰과 오류 응답의 인코딩/디코딩, 타이머 실행·일시정지·만료·이전 시각 경계 통과.
- 최초 메시지 단계에서는 앱 통신을 미검증으로 남겼습니다. 후속 구현과 통합의 검증 범위는 아래 기록을 따릅니다.

## 화면 브랜치 초기 수신 기록

화면 담당의 원본 7개 커밋은 `2af6396`까지 보존했습니다.

| 로컬 브랜치 | 초기 수신 HEAD | 당시 기준과 범위 |
| --- | --- | --- |
| `style/#170-Devin` | `f2990af` | 공통 메시지 `06b5cf2` 위의 선택·권한·준비·시작·중단·연결 화면 |
| `style/#171-Devin` | `2af6396` | #170 위의 진행·타이머·기록 화면과 공통 흐름 후속 수정 |

#173의 실제 Client는 초기 수신 당시 이 화면 브랜치에 반영되지 않았습니다. 현재는 부모 통합을 완료했습니다. 최종 PR 분리 때는 통신 기준을 맞추고 #171에 포함된 #170 후속 수정도 설명합니다. 현재 #170 첫 커밋은 807줄 추가 규모이므로 PR 공개 전 추가 분리 가능성을 검토해야 하며, 아직 리뷰 가능한 최종 diff로 확정하지 않았습니다.

### 수신된 검증 범위

- 화면 담당 보고: SwiftLint 15파일, Swift 파싱, 자산 컴파일, 집중 검사 8개 통과.
- 외부 집중 검사 harness를 제품 잠금 전이 의존성에 맞추는 과정은 SwiftPM trait 해석 오류로 실패했습니다. 대체 harness 결과를 제품 전체 타입검사·빌드 성공으로 확대하지 않습니다.
- Watch 전체 빌드·실제 통신·캡처·저장·기기 UI는 미검증입니다. 기록 bridge가 미주입되어 기록 버튼은 비활성 상태이며, 통합 전에는 전체 완료가 아닙니다.

### 통합 시 대조할 계약

1. `requestStatus`는 새 요청 ID와 조회 대상 원래 요청 ID를 구분합니다. 응답 ID가 소비 경로와 일치해야 합니다.
2. Watch 준비 카운트다운 3초와 iPhone 시작 토큰 만료·늦은 실행 게이트가 양립하는지 검증합니다. 늦은 명령을 허용하도록 만료만 늘려 해결하지 않습니다.
3. 사진·영상의 Watch 발급 기록 ID, 미디어 구간 수신, 최종 영구 저장 ACK와 화면의 saved 표시를 대조합니다.
4. 화면의 review/canAutoSave 상태에서 시작하는 자동 저장과 backend 자동 저장을 중복 실행하지 않습니다. 영상의 실제 검토 가능 시점을 확인합니다.
5. 실험 모드·프로토콜 단계 메타데이터 및 타이머 종료와 삭제의 기록 보존 의미를 맞춥니다.
6. 실제 기록 API를 화면 bridge에 연결한 뒤 임시 통합 안내를 정리하고 전체 빌드·회귀를 실행합니다.

## #173 통신·iPhone 처리 연결

도구가 제공한 `t3/watch-experiment-communication` checkout을 유지했습니다. 화면과 기록 구현은
각 담당 변경에서 통합하며, 이 checkout에서 원격 게시를 수행하지 않습니다.

### Watch 소비 API

`LabcordWatchOS.WatchExperimentClient`는 `DependencyValues.watchExperimentClient`로 사용합니다.

- `send(WatchExperimentCommand) async throws -> WatchExperimentResponse`
- `snapshots() async -> AsyncStream<WatchExperimentSnapshot>`
- `isReachable() async -> Bool`

`send`는 3초 이내의 수신 응답을 기다립니다. 변경 명령의 `received` 이후에는 새로운 조회 요청 ID와
원래 명령의 `targetID`로 `requestStatus`를 조회해야 합니다. `processing` 동안 결과를 기다리며,
전송 오류·타임아웃·취소만으로 미실행을 판단하거나 새 ID로 같은 동작을 실행하지 않습니다.
조회 envelope의 `requestID`는 조회 요청 ID이고, 결과는 `targetID`가 가리킨 명령에 해당합니다.
최종 응답의 snapshot은 해당 명령 처리 당시 상태이므로 현재 화면은 구독의 실험 ID와 revision을
기준으로 갱신해야 합니다. 다른 실험의 응답으로 선택 실험을 바꾸지 않습니다.

snapshot 구독은 application context를 받고, 알려진 실험을 2초마다 다시 조회합니다. 최초 선택 시에는
`snapshot` 조회로 대상을 지정합니다. 구독이 끝나면 refresh task가 취소됩니다. 현재 context는 마지막
snapshot 한 개를 전달하므로 여러 실험 복구와 삭제된 대상 확인은 명시적 조회로 보완합니다.
배터리·기기명 메시지의 기존 userInfo observer와 전송 경로는 유지합니다.

### 수신·실행·저장

- iPhone 앱 초기화에서 coordinator를 활성화합니다. 특정 실험 화면 등장에 의존하지 않습니다.
- 변경 요청은 실행 전 Application Support의 보호된 요청 journal에 원자적으로 저장합니다.
  같은 ID·같은 payload는 기존 결과를 반환하고, 다른 payload는 `duplicateConflict`로 거절합니다.
  조회 요청의 재생 기록은 프로세스 메모리에 유지합니다.
- 재기동 시 journal의 `received`·`processing` 요청은 `resultUnknown`으로 반환합니다.
  실험 저장과 journal 결과 저장은 서로 다른 쓰기이므로 이 경계를 넘은 정확히 한 번 실행은 보장하지
  않습니다. 재실행 대신 최신 snapshot과 원래 요청 상태를 함께 확인합니다.
- revision은 보호된 별도 파일에서 원자적으로 증가시킵니다. 실험 모델·SwiftData schema를 추가하지
  않았습니다. journal은 현재 자동 만료·삭제하지 않으며, 보관·정리 정책은 후속 결정이 필요합니다.
- `prepareStart`로 받은 iPhone 소유 토큰은 수신자 단조 시계 기준 3초 동안 유효하고 한 번 소비합니다.
  카운트다운을 마친 직후 준비 요청을 보내고 결과를 받은 뒤 바로 `start`·`resume`을 보냅니다.
  `takePhoto`·`startVideo`도 실행 직전 같은 준비 경로로 발급받은 토큰이 필요합니다.
  준비 요청은 이미 running인 실험에서도 토큰을 발급할 수 있습니다.
- 시작 준비와 실제 신규 시작은 iPhone 마이크 권한이 허용된 경우 진행합니다. 미결정·거부 상태는
  `permissionDenied`이며 iPhone의 기존 권한 흐름에서 권한을 먼저 처리해야 합니다.
- 전면에서는 저장 성공 뒤 진행 화면을 열고, 배경에서는 다음 활성화를 기다립니다. 다른 활성 실험,
  등록·검토·삭제 작업과 충돌하면 거절합니다. 잠금 중 보호 데이터 불가는 명시적으로 실패합니다.
  OS 기동·전면화·사용자 강제 종료 이후 전달은 보장하지 않습니다.
- `recordEntry`는 현재 모델에서 이미 running 중복 진입을 막습니다. Watch 조회는 진입·저장 없는
  경로를 사용합니다. 최초 시작 시각은 비어 있을 때만 기록하고, 화면 진입이 기존 시작을 덮지 않습니다.

### #174 통합 접점과 남은 구현

`PhoneWatchExperimentCoordinator.shared.recordHandler`에 타이머·촬영·기록 확정·취소 handler를
등록합니다. handler는 대상·상태·입력 값을 검증하고 실제 처리·저장이 끝난 뒤 반환해야 합니다.
실패는 throw합니다. 연결되지 않은 명령은 `invalidState`로 실패합니다.

`prepareSessionClose`는 화면에서 진행 중인 미디어를 기존 자식 Feature 액션으로 중지·저장하고,
완료까지 기다리는 async throwing 접점입니다. #174에서 이 경로를 연결한 뒤 기존 `watchControl`로
이어집니다. 현재 기본 경로는 녹음·영상·사진 처리 중이면 `phoneBusy`로 거절합니다.
유휴 상태의 중단·종료는 자식 정리 액션과 실제 세션 해제를 거쳐 기존 `leaveSession`·`complete`
저장 결과까지 기다립니다. 종료는 기존 repository의 타이머 종료를 사용합니다. 실험 중단은 개별
타이머를 일괄 정지하지 않으며, paused 실험의 개별 타이머 명령은 기록 handler가 처리할 수 있습니다.
저장 실패 시 진행 화면과 오류를 유지하고 카메라를 다시 활성화합니다.

일반 `completed`는 실험 명령의 처리 완료입니다. 미디어 영구 저장·Watch 원본 삭제 허용 ACK는
#174 기록 계약에서 별도로 구현·검증해야 합니다. Watch 오프라인 녹음 보존·재전송은 미완료입니다.
명령은 `transferUserInfo` 큐로 보내지 않습니다. Focus 변경을 실행·전면 상태로 사용하지 않습니다.

### #173 항목별 확인 상태

| 요구 | 구현·확인 상태 |
| --- | --- |
| 목록·선택·snapshot·요청 조회 | 양쪽 API 연결, 독립 harness 확인 |
| 준비·마이크 권한·카운트다운·시작 | receiver token·권한·저장 연결. Watch 카운트다운 UI 통합 미완료 |
| 중단·재개·종료·확인 취소 | 실험 상태 연결. 확인 UI와 기록 취소 handler 통합 미완료 |
| 기록 정리 진행·최종 저장 ACK | `processing`과 처리 완료 구분. #174 실제 기록 결과 통합 미완료 |
| 실험 상태·개별 타이머 분리 | snapshot 분리, 종료 시 저장된 타이머 종료. #174 명령 handler 통합 미완료 |
| 연결 끊김·재연결·닫기 | reachability·최신 context·구독 refresh·Task 취소 연결. 실제 통신 미검증 |
| Watch 오프라인 녹음 지속·복구·iPhone 이어 기록 | #174 소유, 통합 미완료 |
| 3초 ACK·늦은 시작·촬영 | 타임아웃·토큰 소비·만료·취소 후 늦은 응답 방어. 실제 지연 전달 미검증 |
| 버전·중복·충돌·revision·순서 역전 | 독립 harness 확인. 기기 간 순서 역전 미검증 |
| 저장 실패·재시도·재기동 결과 유실 | journal 재생·중단 요청 unknown 확인. SwiftData 실패 주입·실기기 미검증 |
| 전면·배경·일시 정지·잠금·미실행·OS 종료·강제 종료 | 보수적 정책 연결. 상태별 페어링 실기기 확인 미완료 |
| 다른 실험·등록·삭제·완료·stale 경합 | 소스 방어·집중 검사. 실제 동시 UI·저장 경합 미검증 |
| 제스처·화면 이탈·Focus 연계 | 기존 제스처에 종료 중 입력 방어. Watch 가이드·Focus 통합 미완료 |
| 양쪽 앱·Simulator·실기기 | 빌드와 독립 검사 결과는 아래 검증 기록. 기기 도구에 Watch·실기기 미노출 |

전체 #173 완료 판정은 보류합니다. 특히 진행 중 미디어의 종료·저장, #174 최종 ACK, Watch 화면
통합, 페어링 실기기 조건 확인이 남아 있습니다.

### 최종 로컬 검증

제품 코드 `c964e90`에서 변경 Swift 16파일의 strict lint와 양쪽 앱 generic Simulator 전체 빌드가
통과했습니다. 전송·iPhone coordinator 집중 harness, 실제 SwiftData 모델의 메모리 저장 검사,
루트 통합 정적 검사도 통과했습니다. harness는 외부 QA 경로에서 실행했고 기존 Tests는 수정하지
않았습니다. 플랫폼 대역을 사용하는 집중 검사와 실제 WCSession·Repository·UI 런타임은 구분합니다.

로그·재실행 스크립트·상세 검증과 Draft PR 초안은
`/Users/hellosunghyun/Documents/Codex/2026-11-05/qa-watch173/`에 있습니다. 전체 빌드는 이 경로의
전용 DerivedData를 사용했습니다. CI·Simulator 화면·페어링 실기기·배경/잠금/종료 상태별 통신과
#174 미디어 최종 저장은 미실행이며 완료 체크하지 않았습니다.

### UI handoff 후 계약 점검

UI `2af6396`을 읽기 전용으로 대조했습니다. requestStatus의 새 조회 requestID 응답은 일치합니다.
사진·영상 targetID는 Watch가 발급한 recordID 그대로 handler에 전달합니다.

`WatchExperimentSnapshot.mode: ExperimentMode?`를 additive로 추가했습니다. 구버전 JSON의
mode 누락은 nil로 decode되며 iPhone은 실제 detail.mode를 보냅니다. 현재 ExperimentProtocol에는
단계 ID·이름 원천이 없어 프로토콜 시간의 순서·중복만 보존합니다.

UI의 prepareStart 완료 후 3초 countdown은 현재 3초 receiver 토큰을 만료시킵니다. 실제 3010ms
만료 focused 검사로 확인했습니다. TTL은 유지했습니다. parent 통합에서는 countdown 후 별도
실행 승인을 받는 단계가 필요합니다. UI의 ready 전용 prepared 액션을 재사용하면 countdown이
반복되므로 승인 확정용 경로를 구분해야 합니다. UI resume와 신규 촬영도 현재 토큰을 보내지 않아
게이트와 불일치합니다. 이 child는 UI 파일을 수정하지 않았습니다.

deleteTimer는 현재 handler 미연결입니다. 기존 iPhone의 목록 제거는 running을 거절하고
타이머 기록을 물리 삭제하지 않습니다. Watch의 실행 중 종료와 단순 목록 제거 의미를 #174에서
맞춰야 합니다. 또한 현재 activeTimers가 finished를 제외해 Watch 완료확인 화면에 필요한 완료
타이머가 snapshot에 남지 않습니다. 완료 표시·dismiss 보존 정책은 미완료 통합 항목입니다.
상세 근거와 parent 요구는 QA 경로의 `ui-contract-review.md`에 기록했습니다.

UI 계약 점검에 따른 optional mode 추가 후 제품 코드 `94120e1`에서 양쪽 전체 native build를
다시 실행해 모두 통과했습니다. 변경 Swift 17파일 strict lint도 위반 0입니다. 이 빌드는 통신
checkout 기준이며 UI child 커밋을 합친 제품 앱의 빌드·실행은 후속 통합 항목입니다.
