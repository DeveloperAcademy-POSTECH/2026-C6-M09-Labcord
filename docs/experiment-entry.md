# 홈과 프로토콜 없는 실험 등록

앱 전체 목표 흐름과 단계별 연결 상태는 [앱 흐름 명세](app-flow.md),
기존 구현의 목적과 반영 순서는 [구현 조사](implementation-audit.md)에 있습니다.

## 사용자 흐름

홈의 추가 버튼에서 실험 등록 화면을 열고 **프로토콜 없이 진행**을 선택하면
`새 실험`을 준비 상태로 저장합니다. 저장 성공 후 홈으로 돌아와 최근 실험에 표시합니다.
등록만으로 녹음·촬영·타이머를 시작하지 않습니다.

```mermaid
flowchart TD
    Launch[앱 실행] --> Home[홈 · 저장된 실험 조회]
    Home -->|추가| Registration[프로토콜 방식 선택]
    Registration -->|뒤로 가기| Home
    Registration -->|프로토콜 없이 진행| Save[UUID를 한 번 발급 · 저장]
    Save -->|성공| Refresh[실제 저장 목록 재조회 · 목록 반영]
    Refresh --> Created[experimentCreated · 최종 이벤트]
    Created --> Home
    Save -->|실패| Retry[화면 유지 · 재시도 또는 취소]
    Retry -->|동일 UUID로 재시도| Save
    Home -->|행 선택| Selected[experimentSelected · 기존 UUID]
    Home -->|왼쪽으로 밀기| Actions[수정 · 삭제]
    Actions -->|수정| Edit[protocolEditRequested · 기존 UUID]
    Actions -->|삭제| Confirm[영구 삭제 확인창]
    Confirm -->|취소| Home
    Confirm -->|삭제 확인| Delete[선택 UUID의 실험 · 연결 기록 저장소 삭제]
    Delete -->|성공| Home
    Delete -->|실패| DeleteError[항목 유지 · 재시도 또는 취소]
    DeleteError -->|동일 UUID 재시도| Delete
```

진행·일시 정지는 진행 중인 실험, 준비·종료는 최근 실험에 표시합니다.
각 그룹은 생성일 최신순이며 동일 시각은 UUID 문자열로 순서를 고정합니다.
목록이 비었을 때도 추가 버튼을 사용할 수 있고, 실제 저장소에 예시 데이터를 넣지 않습니다.

## 구현 책임과 연결 계약

구현은 iPhone 앱의 `Researchers/Features/ExperimentEntry/`에 있습니다.

| 구성 | 책임 |
| --- | --- |
| `ExperimentEntryFeature` | 목록·등록·저장 상태, 중복 요청 차단, 재시도, delegate 이벤트 |
| `ExperimentEntryView` | 화면 이동, 오류 경고창, Feature에 Action 전달 |
| `Presentation/` | Figma 기반 화면·실험 행·배지·입력 방식·버튼 표현 |
| `ExperimentListEntry` | 저장 객체에서 분리한 Sendable 목록 값과 상태 투영 |
| `Persistence/` | iPhone SwiftData 생성·조회·삭제와 TCA 의존성 경계 |

하나의 저장소 인스턴스가 ModelContainer를 유지합니다. 각 작업은 별도 ModelContext를 사용하고
자동 저장을 끕니다. `create`는 같은 UUID가 이미 저장됐으면 기존 항목을 반환합니다.
실패한 작업의 context는 다른 화면의 미저장 변경을 rollback하지 않습니다.
저장소 초기화 실패는 다음 조회에서 재시도하며 기존 데이터를 삭제하거나 초기화하지 않습니다.

저장 후 실제 목록을 재조회하고 Feature 목록에 반영한 다음 `experimentCreated`를 보냅니다.
재조회에 실패해도 저장된 항목을 유지하고 목록 조회 오류로 구분합니다. 이때 재시도는 조회만
수행하며 실험을 다시 만들지 않습니다. 성공 delegate 뒤에는 Entry 액션을 보내지 않으므로
부모가 해당 이벤트에서 Entry 상태를 제거하거나 후속 화면으로 전환할 수 있습니다.

기존 공유 `Experiment` 모델을 변경하지 않습니다. 생성값은 `title = "새 실험"`,
`status = .preparing`, `procedure = nil`, `startedAt = nil`입니다.
준비 상태 이력은 기존 생성자가 만듭니다. 실패 후 재시도도 같은 UUID를 사용하며,
저장 중 추가 입력과 뒤로 가기를 막습니다. 취소한 등록은 실험을 만들지 않습니다.

부모 TCA Feature에서 Entry를 조합하고 아래 delegate Action을 처리하면 후속 화면을 연결할 수 있습니다.

| Delegate | 의미 |
| --- | --- |
| `.experimentCreated(UUID)` | SwiftData 저장에 성공한 실험. 이번 흐름에서는 홈 복귀 |
| `.experimentSelected(UUID)` | 홈에서 선택한 기존 실험 |
| `.protocolEditRequested(UUID)` | 밀어서 표시한 수정 버튼. 선택 실험의 프로토콜 수정 연결 지점 |
| `.protocolSourceRequested(ProtocolSource)` | 사진·파일·최근 프로토콜의 실제 입력 연결 지점 |
| `.settingsRequested` | 설정 화면 연결 지점 |

이후 실험 화면을 연결할 때는 전달받은 UUID로 같은 저장소의 실험을 조회해야 합니다.
현재 저장소 API는 목록 값 조회·생성·삭제이며, Experiment 원본 조회 API와 후속 화면의
ModelContainer 주입은 아직 연결하지 않았습니다. 기록·타이머를 연결하기 위해 UUID를
새로 만들지 않습니다.
사진·파일 입력, 프로토콜 분석·재사용, 설정 화면과 이후 실험 화면은 이번에 연결하지 않았습니다.
자료를 선택하지 않은 상태의 다음 버튼은 비활성입니다. 화면의 10장·1GB는 디자인 문구이며
입력 지원 상한을 기술적으로 검증했다는 의미가 아닙니다.

## 밀어서 수정·삭제

진행 중인 실험과 최근 실험 모두 왼쪽으로 밀면 수정·삭제 버튼이 나타납니다.
iOS27의 기본 `swipeActions`·`swipeActionsContainer`를 사용해 기존 ScrollView 배치를 유지합니다.
끝까지 밀어도 바로 실행하지 않습니다. 수정은 기존 UUID로 `protocolEditRequested`를 전달하며,
프로토콜 수정 화면과 실제 편집은 아직 구현하지 않았습니다.

삭제 버튼은 실험명과 영구 삭제 경고가 있는 확인창을 엽니다. 취소하면 저장소를 건드리지 않습니다.
확인하면 해당 UUID의 Experiment를 별도 ModelContext에서 삭제하고 저장합니다.
기존 모델의 cascade 규칙으로 기록·타이머 중단·실험 중단·상태 이력이 함께 삭제됩니다.
다른 실험은 보존하며 이미 없는 UUID의 삭제 요청은 성공한 것으로 처리합니다.
`filePath` 문자열이 가리키는 외부 미디어 파일의 삭제는 포함하지 않습니다.
현재 Entry는 미디어 파일을 생성·저장하지 않으며, 파일 소유권·수명 관리는 후속 기록 흐름에서 연결해야 합니다.

저장 성공 전까지 목록 항목을 유지하고 실패하면 오류 경고창에서 같은 UUID로 재시도합니다.
삭제 성공 Action을 0.25초 ease-in-out transaction으로 전달해 아래 행과 다음 섹션이 빈 공간을
채웁니다. 실패·취소·일반 조회·등록에 같은 애니메이션을 추가하지 않습니다.
삭제 중 목록 조회·중복 삭제·새 등록·행 선택·수정 요청을 차단하고, 이전 조회 응답이 삭제한 행을
다시 표시하지 못하도록 조회 revision을 갱신합니다. 진행 중인 실험을 삭제해도 현재 별도 Watch
세션이나 녹음·타이머 중단 명령은 보내지 않습니다. 해당 흐름은 Entry에 아직 연결되지 않았습니다.

## 디자인시스템 교체

원본은 Figma 파일 `v6cxQ2I6zURWYQaG5pnuBL`의 홈 `502:12299`, 등록 `502:12563`입니다.
기존 LabcordDesignSystem API는 사용하지 않습니다.
PR 반영 순서와 기존 화면의 구현 목적은 [구현 조사](implementation-audit.md)에 정리합니다.

```mermaid
flowchart LR
    Feature[TCA 상태와 Action] --> Screen[화면 View]
    Screen --> Presentation[표시 컴포넌트]
    Presentation --> Appearance[EntryAppearance · 현재 Figma 스타일]
    Presentation -. 추후 내부 교체 .-> DesignSystem[디자인시스템 컴포넌트]
    Feature --> Persistence[SwiftData 저장 계층]
```

교체 지점은 `EntryAppearance`, `EntryText`, `HomeExperimentRow`와 내부 배지,
`EntryRoundButton`, `ProtocolRegistrationView` 내부 입력 항목·다음 버튼입니다.
표시 컴포넌트는 Store와 ModelContext를 참조하지 않고 값과 콜백을 받습니다.
따라서 교체 시 Feature·저장소·UUID 이벤트 계약은 유지할 수 있습니다.
### 폰트와 아이콘

2026-10-28 사용자 요청에 따라 모든 Entry 텍스트는 SwiftUI 기본 `Text`와 시스템 폰트를
사용합니다. 한글 폰트 파일·문자별 폰트 등록·자간과 베이스라인 보정·커스텀 TextRenderer는 제거했습니다.
OS의 글자 윤곽과 렌더링 차이를 허용하며, 이전 Noto 적용 화면의 비교 수치를 현재 결과로 사용하지 않습니다.

| 역할 | 크기 / 행높이 | 굵기 |
| --- | --- | --- |
| headline | 17 / 22pt | semibold |
| body | 17 / 22pt | regular |
| subheadline·날짜 | 15 / 20pt | regular |
| footnote | 13 / 18pt | regular |
| caption | 12 / 16pt | regular |
| title | 20 / 25pt | regular |

아이콘은 위 Figma 원본에서 내보낸 SVG4개와 표시용 template PNG12개(1x·2x·3x)를 사용합니다.
사전 생성 PNG는 설정·추가48pt, 뒤로44pt, 행 화살표11×20pt 크기에서 표시하고,
지원 밖 크기·배율에서는 SVG로 표시합니다. 배경·그림자·접근성·액션은 SwiftUI 코드입니다.

| 아이콘 | Figma 원본 leaf | 표시 자산 |
| --- | --- | --- |
| 설정 | `I502:12342;5522:11872;5522:11881` | EntryGear·EntryGearSampled |
| 추가 | `I502:12341;5522:11869;5522:11894` | EntryPlus·EntryPlusSampled |
| 뒤로 | `I502:12585;6491:22970;5431:837` | EntryBack·EntryBackSampled |
| 행 화살표 | `502:12307` | EntryChevron·EntryChevronSampled |

원본 SVG를 변경하지 않고 고정 표본으로 생성합니다. 출처 SHA·원점·계산과 출력 검증은
`prepare-entry-symbols.py`와 `export-entry-symbols.swift`에 있습니다.
앱 실행·빌드 때 재계산하지 않습니다. 기존의 부팅된 전용 Simulator와 저장소 밖의 새 출력 폴더를 사용합니다.

```sh
python3 scripts/verification/prepare-entry-symbols.py \
  --simulator-udid 전용_SIMULATOR_UDID \
  --output /tmp/labcord-entry-symbol-output
```

## 시뮬레이터 검증

실제 앱 빌드와 SwiftLint는 저장소의 기존 명령을 사용합니다.
아래 호스트는 앱 프로젝트·패키지 설정에 테스트 타깃을 추가하지 않고,
실제 Entry 소스와 `Tests/ExperimentEntry/`를 참조하는 별도 Xcode 프로젝트를 생성합니다.
Python 표준 라이브러리 외에 생성 도구 설치는 필요하지 않습니다.

```sh
python3 scripts/verification/generate-entry-qa.py /tmp/labcord-entry-qa
xcodebuild test \
  -project /tmp/labcord-entry-qa/EntryQA.xcodeproj \
  -scheme EntryQA \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/labcord-entry-results.xcresult \
  CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict
```

결과 경로는 새 경로를 사용합니다. 검증 앱은 별도 bundle ID와 저장소를 사용하며,
초기화 플래그도 검증 앱 자신의 저장소에만 적용됩니다.
검증용 fixture는 메모리 저장소를 사용합니다. 제품 앱에는 검증 플래그나 예시 데이터가 없습니다.

검증 항목은 저장·재조회·최종 이벤트 순서와 부모의 Entry 제거, 재조회 실패 후 조회만 재시도,
저장 실패 후 동일 UUID 재시도, 중복 입력·저장 중 이탈 차단,
오래된 조회 결과 무시, 실제 디스크 재개방, 앱 재실행, 입력 이벤트와 뒤로 가기입니다.
삭제는 확인·취소, 실패 후 동일 UUID 재시도, 중복·오래된 응답 차단, 연쇄 삭제와 다른 실험 보존,
디스크 재개방·앱 재실행 후 유지 및 수정 delegate의 UUID도 확인합니다.
화면 캡처는 iPhone 17의 402×874pt 전체 화면을 두 Figma 화면과 각각 대조합니다.
XCTest 첨부 캡처와 실행 결과를 확인하며, 빌드 성공을 화면 일치나 테스트 통과로 대신하지 않습니다.

### 현재 검증 결과와 제한

2026-10-28 기준 iOS27.0 전용 iPhone17 Simulator에서 Entry 단위16개가 통과했습니다.
실제 Researchers 시뮬레이터 빌드, SwiftLint strict56파일·위반0, 문서 검사·공백 검사도 통과했습니다.
갱신한 두 Mermaid는 공식 CLI로 구문분석·SVG 렌더를 확인했습니다.

UI6개는 외부 simctl 프로세스가 전용 시뮬레이터를 반복 종료해 중단됐으며,
사용자 요청에 따라 **UI 검증과 최신 화면 비교를 보류**했습니다. 통과나1:1 일치로 표시하지 않습니다.
수정 화면·외부 미디어 정리·Watch 세션 중단·Dynamic Type은 검증 범위에 포함되지 않습니다.
기존 제품 저장소를 초기화하거나 검증 중 실제 실험을 삭제하지 않았습니다.

Simulator의402×874pt·3x 원시 캡처를 같은 크기의 Figma 원본과 비교합니다.
`compare-entry-png.py`는 정렬·리사이즈·마스크·임계치 없이 전체 RGB·alpha 차이를 계산하며,
종료0은 분석 성공입니다. 화면 동일 여부는 출력의 `pixelsIdentical`로 판단합니다.
폰트가 달라져 발생하는 차이를 숨기거나 이전 빌드·외부 시제품의 수치를 현재 결과로 대체하지 않습니다.

```sh
python3 scripts/verification/compare-entry-png.py \
  /외부/Figma-원본-3x.png /외부/Simulator-원시-3x.png \
  --output /tmp/labcord-entry-new-comparison.json
```

상세 캡처·실험 이력·xcresult는 저장소 밖 `Labcord-NoProtocol-QA-2026-10-28/`에 보관합니다.
폰트 비교 도구와 별도 폰트·아이콘·검증 이력 문서는 PR에서 제외하고,
이 안내에 현재 유지보수·재현에 필요한 계약과 명령만 모았습니다.
