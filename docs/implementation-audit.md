# 구현 목적과 PR 반영 현황

확인일: 2026-10-28 KST. GitHub의 PR `merged_at`·대상 브랜치와 로컬 Git 이력을
대조했다. `closed`는 병합 완료를 뜻하지 않으며, 다른 기능 브랜치에 병합된 PR도
`develop` 반영과 구분한다. 아래 시간은 GitHub `merged_at`을 KST로 변환한 값이다.

## 비교 기준

| 기준 | 커밋 | 의미 |
| --- | --- | --- |
| 팀 `develop` | [`e31d08b`](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/commit/e31d08bbef0de804eb982051eaab7815a04baf6f) | 이번 Entry 작업을 시작한 기준. #61 CI 변경까지 반영 |
| 별도 세션 기능 브랜치 `feat/#57-Theo` | [`021b0c2`](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/commit/021b0c2bd9956150f9f4ec48c0c26aef2b8d3619) | 카메라·타이머·화면 꺼짐 방지 기능. 위 develop과 별도 |
| 이번 작업 `hellosunghyun/no-protocol-experiment` | `c01f714`까지의 Entry 관련 커밋 | 홈·프로토콜 없는 등록·SwiftData 저장·UUID 이벤트 추가. 기존 develop 구현과 구분 |

현재 팀 저장소 이름은 `DeveloperAcademy-POSTECH/2026-C6-M09-Labcord`다.
개인 포크 `hellosunghyun/2026-C6-M09-Researchers`의 같은 번호 PR과 혼동하지 않는다.
이 문서의 PR 번호와 링크는 모두 팀 저장소 기준이다.

## develop에 실제 반영된 순서와 목적

아래는 화면·데이터 구조 및 관련 협업 기능 중심의 반영 순서다. 각 병합 커밋이
`e31d08b`의 조상임을 `git merge-base --is-ancestor`로 확인했다.

| PR | 병합 시각 KST | 대상 / 병합 커밋 | 구현 목적과 범위 | 코드·문서 위치 |
| --- | --- | --- | --- | --- |
| [#20](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/20) | 10-20 13:07:24 | `develop` / `ad33c98` | Apple Watch 함께 사용 여부를 묻는 페어링 화면 UI. 실제 워치 정보 통신은 후속 #28 | [WatchPairingView](../Researchers/Features/WatchPairing/WatchPairingView.swift) |
| [#28](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/28) | 10-23 00:15:32 | `develop` / `9f0f189` | 실험 전 워치 사용 가능 여부·모델명·배터리 표시. iPhone 요청과 Watch 응답, 상태 스트림·취소 처리 | [WatchPairingFeature](../Researchers/Features/WatchPairing/WatchPairingFeature.swift), [iOS 통신](../Packages/ResearchersModules/Sources/LabcordiOS/WatchConnectivity), [Watch 통신](../Packages/ResearchersModules/Sources/LabcordWatchOS/WatchConnectivity) |
| [#52](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/52) | 10-24 12:45:07 | `develop` / `6191830` | 공유·디자인시스템·플랫폼별 타깃 분리와 WatchConnectivity 패키지 이전. 제품 기능 자체를 추가한 변경과 구분 | [Package.swift](../Packages/ResearchersModules/Package.swift) |
| [#30](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/30) | 10-24 22:49:32 | `develop` / `99069da` | 화면 캡처·녹화 차단의 기술검증 문서. 제품 앱에 차단 기능을 연결한 PR은 아님 | [Screencapture 검증 문서](Technical%20Verification/Screencapture/README.md) |
| [#53](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/53) | 10-24 23:25:40 | `develop` / `e9e347f` | 실험·기록·일시 정지·상태 이력을 나타내는 SwiftData 모델과 프로토콜 자료형. 화면의 저장 실행·조회 연결과 구분 | [공유 Models](../Packages/ResearchersModules/Sources/LabcordShared/Models) |
| [#56](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/56) | 10-25 17:15:53 | `develop` / `c5b20df` | 기록 대기 모드 전환 안내 UI. 파일 업로드·프로토콜 방식 선택 화면은 아니며 시작 버튼의 이동 액션은 비어 있음 | [ExperimentSetupView](../Researchers/Features/ExperimentSetup/ExperimentSetupView.swift) |
| [#51](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/51) | 10-25 20:04:57 | `develop` / `3480d8b` | CODEOWNERS의 자동 리뷰 요청 대상을 개발팀으로 한정 | [CODEOWNERS](../.github/CODEOWNERS) |
| [#62](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/62) | 10-25 21:24:53 | `develop` / `af1dcd5` | 가로 실험 화면의 제목·기록·타이머 영역을 나누고 가로/세로 View 분리. 당시 카메라·타이머는 화면 틀 | [ExperimentSession](../Researchers/Features/ExperimentSession) |
| [#64](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/64) | 10-26 01:35:15 | `develop` / `cdf7e5e` | 세로 실험 화면과 드래그 가능한 커스텀 바텀시트. 시트 이동에 기록 버튼이 함께 따라가는 UI | [PortraitSessionView](../Researchers/Features/ExperimentSession/Layouts/PortraitSessionView.swift), [PortraitSessionSheetView](../Researchers/Features/ExperimentSession/Sections/PortraitSessionSheetView.swift) |
| [#59](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/59) | 10-26 23:16:13 | `develop` / `0da9b20` | 이슈 담당자·닉네임 라벨 동기화, PR 담당자 상속·유형 라벨 관리 자동화 | [자동 지정 workflow](../.github/workflows/auto-assign.yml) |
| [#61](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/61) | 10-27 12:43:25 | `develop` / `e31d08b` | 문서·lint 설정·앱 코드 등 변경 범위에 따라 Build·SwiftLint 실행 여부 결정 | [변경 판별 스크립트](../.github/scripts/detect-changes.sh), [Build](../.github/workflows/build.yml) |

`e31d08b`의 앱 진입점은 `WatchPairingView`였다. 페어링의 두 진행 버튼과 대기 화면의
시작 버튼은 화면 이동을 수행하지 않았다. 실험 세션 reducer는 타이머 탭 선택만 처리하며,
기록 버튼 액션·카메라 화면·타이머 목록은 실행 기능과 연결되지 않았다.
공유 실험 모델에 UUID는 있었지만 앱의 ModelContainer·목록 조회·등록 저장은 없었다.
따라서 모델·화면 UI의 존재를 연결된 제품 흐름의 완성으로 해석하지 않는다.

## 별도 브랜치에만 병합된 세션 기능

| PR | 병합 시각 KST | 실제 대상 / 병합 커밋 | 구현 목적 | develop `e31d08b`와 이번 Entry의 상태 |
| --- | --- | --- | --- | --- |
| [#66](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/66) | 10-26 12:46:14 | `feat/#57-Theo` / `f00a759` | 카메라 권한·프리뷰 세션·회전 유지·전후면 전환. 줌은 후속 범위 | 미반영. 해당 PR의 `LabcordiOS/Camera`와 세션 변경 참조 |
| [#74](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/74) | 10-27 11:40:34 | `feat/#57-Theo` / `aaa2520` | 설정·직접 입력 타이머 실행, 일시 정지·재개·삭제, 자유/프로토콜 모드 | 미반영. 해당 PR의 `LabcordShared/Timers`, `ExperimentMode`, 세션 변경 참조 |
| [#77](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/77) | 10-27 14:32:53 | `feat/#57-Theo` / `021b0c2` | 실험 화면 진입 시 화면 꺼짐 방지, 이탈 시 시스템 설정으로 복원 | 미반영. 해당 PR의 실험 세션 생명주기 변경 참조 |

이 세 PR은 위 순서로 같은 기능 브랜치에 쌓였다. 같은 주제의
[#76](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/76)은
`develop` 대상으로 열렸지만 **병합 없이 닫혔으며**, 실제 병합은 #77이다.
세션 기능 브랜치의 `Experiment`에는 `mode: ExperimentMode = .free`가 추가됐지만,
이번 Entry는 develop의 기존 모델을 그대로 사용한다. UUID 계약을 연결할 때 이 차이를 확인한다.

## 닫혔지만 병합되지 않은 문서 파싱 PR

| PR | 당시 대상 브랜치 | 역할 | GitHub 상태 |
| --- | --- | --- | --- |
| [#26](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/26), [#27](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/27) | `develop` | 온디바이스 문서 파싱·OCR 전체 구현 초안 | closed / `merged_at = null` |
| [#41](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/41) | `develop` | OfficeOxide 런타임 자산·고지 | closed / `merged_at = null` |
| [#42](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/42) | `chore/#33-Devin` | 파싱 입력·결과 API와 형식·컨테이너 검증 | closed / `merged_at = null` |
| [#43](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/43) | `feat/#34-Devin` | 이미지 OCR·텍스트 문서 파싱 | closed / `merged_at = null` |
| [#44](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/44) | `feat/#35-Devin` | PDF 본문·표·삽입 이미지 추출 | closed / `merged_at = null` |
| [#45](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/45) | `feat/#36-Devin` | Office·HWP·HWPX 파싱 | closed / `merged_at = null` |
| [#46](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/46) | `feat/#37-Devin` | 배치 병렬 처리·메모리 예산 | closed / `merged_at = null` |
| [#47](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pull/47) | `feat/#38-Devin` | 파싱 API 사용법·형식별 제약 | closed / `merged_at = null` |

#41→#47은 리뷰를 나눈 스택의 순서이며 develop에 병합된 순서가 아니다.
`merge_commit_sha`가 반환되더라도 병합 전 비교용 커밋일 수 있으므로 병합의 근거로
단독 사용하지 않는다. `e31d08b`와 이번 Entry에는 이 파서 스택이 없고, 사진·파일 입력에서
파싱을 호출하지 않는다. [기술검증 목록](Technical%20Verification/README.md)의 완료 표시는
기술검증 상태이며 앱 기능의 통합 완료와 구분한다.

## 최신 대화와 이번 선행 작업

제공된 `KakaoTalk_Chat_…_2026-10-28-00-00-56.csv`의 날짜 범위는
2026-05-05~2026-10-27이다. **2026-10-28 대화 행은 0개**이고 최신 10월 27일의
31개 행 중 작업 합의를 확인했다. 대화 참여자 정보와 원문은 저장소에 보관하지 않는다.

최신 합의는 10월 28일까지 홈에서 실험을 추가하고, 프로토콜 방식 선택에서
프로토콜 없이 진행하는 경로를 준비하는 것이다. 뒤의 화면 연결과 타이머·기록을 같은
실험에 귀속하려면 먼저 영구 저장된 UUID가 필요하므로, 홈 표시만으로 완료하지 않는다.
이 선행 경로를 만든 뒤 후속 실험 화면 연결은 별도 작업에서 담당한다.

이번 화면 원본은 요청한 [Figma 페이지](https://www.figma.com/design/v6cxQ2I6zURWYQaG5pnuBL?node-id=502-7591)의
[홈 `502:12299`](https://www.figma.com/design/v6cxQ2I6zURWYQaG5pnuBL?node-id=502-12299)와
[등록 `502:12563`](https://www.figma.com/design/v6cxQ2I6zURWYQaG5pnuBL?node-id=502-12563)이다.
컴포넌트 구현 여부와 화면 전체의 1:1 일치는 구분하며, 화면 검증은 iPhone 17
시뮬레이터 402×874pt의 실제 캡처로 각각 대조한다.

## 이번 Entry에서 추가된 동작과 이후 연결

연결된 [Manyfast 문서](https://manyfast.io/editor/5ece826d-ca56-4e8c-94d3-6dcdb1a301f8?map=prdMap)의
`F-MBXOFY`(프로토콜 기반 실험 등록)는 자료 없는 등록도 허용하고, 기본 이름을 `새 실험`으로
정하며 등록과 실제 기록 시작을 분리한다. `F-ZAUWYG`(실험 선택과 진행 제어)는 진행 중인
실험·최근 실험의 분리와 이름·날짜·상태 배지를 정의한다. `PL-FZNOVP`는 등록 직후 상태를
준비로 정의한다. 이번 Entry는 이 중 홈과 프로토콜 없는 등록의 선행 경로를 연결한다.
Manyfast 전체 기능을 구현 완료한 의미는 아니며, 외부 문서의 진행 상태는 변경하지 않았다.

확인 시점 문서에는 실험명 편집, 사진·파일 선택, 분석 결과 검토, 실험 시작·중단·재개와
기록 정리 등 후속 요구사항도 있다. 이 요구사항은 아래 UUID 계약 이후의 별도 연결 대상이며,
삭제하거나 이번 화면의 비활성 버튼을 기능 완료로 표시하지 않는다.

| 관련 로컬 커밋 | 추가·수정 목적 |
| --- | --- |
| `0aecc56` | 홈 목록·상태 배지·추가/설정 표시 컴포넌트 |
| `3b6a7e9` | 프로토콜 방식 선택 화면과 입력별 이벤트 |
| `4233ca2` | 실제 앱 루트를 홈으로 전환, 프로토콜 없는 실험의 SwiftData 저장·UUID delegate |
| `869449b` | 별도 시뮬레이터 QA 호스트·저장 및 화면 회귀 테스트 |
| `9f86049` | 저장 후 실제 목록 재조회와 QA 호스트 연결 보완 |
| `c01f714` | 저장→재조회→목록 반영→최종 delegate 순서, 부모 child 제거·조회 실패 회귀 테스트 |

실제 루트는 [ResearchersApp](../Researchers/App/ResearchersApp.swift)의 Entry Store/View다.
[EntryFeature](../Researchers/Features/ExperimentEntry/ExperimentEntryFeature.swift)는
`프로토콜 없이 진행`에서 UUID를 한 번 발급하고 `새 실험`을 `.preparing` 상태로 저장한다.
저장 성공 후 홈으로 복귀하며, 실패 시 등록 화면에서 같은 UUID로 재시도할 수 있다.
저장 후 목록 조회만 실패하면 저장된 항목을 유지하고 조회 오류로 구분한다.
최종 성공 delegate 뒤에는 child 액션을 보내지 않으므로 부모가 Entry 상태를 제거할 수 있다.

[저장소](../Researchers/Features/ExperimentEntry/Persistence/ExperimentEntryRepository.swift)는
iPhone에서 ModelContainer를 유지하고 작업별 ModelContext를 사용한다. 기존 실험 모델은
변경하지 않았고 실제 저장소에 예시 데이터를 넣지 않는다. 표시 컴포넌트는 값·콜백을 받아
디자인시스템으로 내부 표현을 교체할 수 있다. 이번 화면은 기존 LabcordDesignSystem API에
연결하지 않았다. 상세 계약과 재현 명령은 [Entry 구현 안내](experiment-entry.md)를 따른다.

현재 완료 범위는 홈 조회·프로토콜 없는 등록·저장 후 UUID 이벤트까지다.
실험 행 선택·설정·사진·파일·최근 프로토콜은 delegate 연결 지점만 있으며,
제품 앱 루트에는 아직 후속 처리자가 없다. 등록만으로 촬영·녹음·타이머를 시작하지 않는다.
**저장소의 공개 호출 범위는 목록 DTO 조회·생성뿐이며, UUID로 Experiment 원본을 읽는 API와
후속 화면의 ModelContainer 환경 주입은 아직 없다.** 후속 구현은 저장된 UUID를 유지하며
동일 저장소에서 조회하는 경계를 먼저 연결해야 한다.

## 재확인 방법

```sh
gh api 'repos/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/pulls?state=closed&per_page=100' \
  --jq '.[] | {number, base: .base.ref, merged_at, closed_at, merge_commit_sha, html_url}'
git log --first-parent --reverse --format='%h %cI %s' e31d08b
git merge-base --is-ancestor ad33c98 e31d08b
git log --reverse --oneline e31d08b..c01f714
```

위 명령은 PR 상태와 반영 이력을 확인하는 읽기 전용 명령이다. 앱 빌드·테스트·화면 일치의
실행 결과는 별도로 확인해야 하며, 이력 조회 성공을 기능 검증 완료로 표시하지 않는다.
