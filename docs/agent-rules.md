# Agent Rules·Skills 관리 가이드

[이슈 #32](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/issues/32)는
기존 팀 협업 규칙을 에이전트가 사용할 수 있는 형태로 옮깁니다.
앱·의존성·CI를 바꾸거나 새로운 팀 정책을 정하는 작업이 아닙니다.

## 사용 방법과 구조

에이전트에는 저장소 루트의 [AGENTS.md](../AGENTS.md)를 읽게 합니다.
작업에 해당하는 Skill만 추가로 읽으면 됩니다. 세부 규칙은 각 Skill 한 곳에서 관리합니다.

```text
AGENTS.md                              공통 원칙·저장소 지도·작업별 링크
.agents/skills/
├── code-style/SKILL.md                 Swift 스타일
├── architecture/SKILL.md               TCA·모듈·기기별 저장/통신 책임
├── git-workflow/SKILL.md               브랜치·커밋·이슈·PR·리뷰
└── verify-change/
    ├── SKILL.md                        변경별 검증 기준·명령·결과 보고
    └── scripts/check_agent_docs.sh     Bash 문서 형식·로컬 파일 링크 검사
docs/agent-rules.md                     출처·차이·인식 검증·관리 방법
```

가까운 협업 절차인 Git·PR을 하나로 묶고, 일반 문서 작업을 위한 별도 Skill은 만들지 않았습니다.
참고자료와 템플릿은 기존 파일·공식 문서 링크를 재사용합니다. 빈 `references/`나 `assets/`는 만들지 않습니다.
에이전트를 쓰지 않는 팀원은 기존 Xcode·Git 작업을 그대로 할 수 있습니다.
이 파일들은 hook·자동 실행·패키지 설치·CI 변경을 추가하지 않습니다.

## 출처와 적용 범위

기준 자료는 [Notion 개발 컨벤션](https://sassy-cloth-fbe.notion.site/3fa06046c66e804eb90bcfb3d7341498)입니다.
이번 반영은 테오가 작성한 컨벤션의 사용자 제공 ZIP 사본을 기준으로 했습니다.
원문 작성일 표기는 2026-10-15, export의 관측일 표기는 2026-10-26입니다.
온라인 Notion의 현재 내용까지 대조했다는 의미는 아닙니다.

| 원문 항목 | 반영 위치·분류 |
| --- | --- |
| Branch | git-workflow: 브랜치 형식 |
| Commit·Commit Message | git-workflow: 종류와 커밋 형식 |
| Pattern/Architecture·개발 사용 기술 | architecture: Swift·TCA·SwiftData |
| Issue·Pull Request | git-workflow: 제목 형식·기존 PR 템플릿 |
| Git·Code Review | git-workflow: Git Flow 참고·CodeRabbit·팀원 승인 |
| Code Style | code-style: StyleShare·API 이름·로컬 lint 설정 |
| 폴더 구조·운영 규칙 1 | architecture: 책임은 유지하고 현재 경로로 매핑 |
| Feature 작성 규칙 2 | architecture: View/Feature 역할·내부 참조 제한 |
| 데이터 저장과 전송 3 | architecture: iPhone 저장·Watch 전송·완료 상태·중복 방지 |
| Shared와 DesignSystem 기준 4 | architecture: 공통화 시점·UI 책임·패키지 연결 |
| 자동 생성 연결 문서 목록 | 필요 시 원문 링크로 참조; 각각을 새 팀 정책으로 승격하지 않음 |
| 이슈 #32의 실행·생략 기준 | verify-change: 변경 종류별 빌드·SwiftLint |
| 항상 필요한 적용·보고 원칙 | AGENTS.md; 명령·상세 절차는 Skill로 분리 |

ZIP에 포함된 TCA·Dependencies·Navigation·Testing·Swift API 설계 등 연결 문서는
상세 기술 참고자료입니다. 모든 예제나 `main` 브랜치 API를 팀의 필수 규칙으로 옮기지 않습니다.
현재 의존성은 [Package.resolved](../Researchers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved),
모듈 구성은 [Package.swift](../Packages/ResearchersModules/Package.swift)를 확인합니다.

`deep-research-report (2).md`는 짧은 공통 Rules, 필요할 때 읽는 Skills,
결정론적 보조 검사라는 **설계 사례**로 참고했습니다.
검증되지 않은 모델 성능·출시일·제품별 자동 탐색 주장은 저장소 규칙에 반영하지 않았습니다.

### 원문 사본 식별

아래 SHA-256은 ZIP 전체가 아닌 추출된 파일의 원본 바이트 기준입니다.

| 파일 | SHA-256 |
| --- | --- |
| `개발 컨벤션.md` | `00fa25cbd528454a740e1c0cef2c4cc77f40c028e12e106977ae94194545ce52` |
| ZIP의 `0003--StyleShare-…가이드.md` | `ae75895dd8a0c11e5f11d6da876155443310a07c359ba68cc27d791a1d11b233` |

전체 ZIP을 저장소에 복제하지 않습니다. 해시는 다음 export와의 비교 기준이며,
온라인 문서 변경이나 규칙의 의미 차이를 자동 감지하지 않습니다.

## 원문과 현재 구현의 차이

| 원문·참고자료 | 현재 저장소·처리 |
| --- | --- |
| `ResearchWatch Watch App/` | 소스 경로는 `ResearchWatchApp/`, 스킴 이름은 `ResearchWatch Watch App` |
| `Packages/Shared`, `Packages/DesignSystem` | 단일 `Packages/ResearchersModules/Package.swift` 아래 네 개 타깃. 경로 변경을 지시하지 않음 |
| 앱별 `Data`/`Database` 표기 혼재 | 기기별 구현은 `LabcordiOS`·`LabcordWatchOS`에도 있음. 새 저장 구현의 경로 결정은 해당 작업에서 팀과 확인 |
| Watch에 SwiftData 저장을 두지 않음 | `LabcordShared/Models`의 기존 모델 선언과 기기의 실제 저장 실행 책임은 구분. 기존 모델을 자동 이동하지 않음 |
| StyleShare 들여쓰기 2 spaces | 기존 Swift는 주로 4 spaces. 팀 적용 기준 확인 사항이며 이번 작업에서 포맷을 바꾸지 않음 |
| StyleShare 내장 import 후 외부 import 그룹 | 기존 코드 배치와 차이가 있음. `.swiftlint.yml`의 `sorted_imports`도 함께 확인하며 새 우선순위를 임의 확정하지 않음 |
| StyleShare 최대 99자 | 로컬 설정은 warning 99·error 150이고 `--strict`는 warning도 실패 처리 |
| Package의 iOS/watchOS 최소 26 | Xcode 프로젝트 배포 대상은 27.0, CI runner는 `xcode-27`, Swift tools는 6.4 |
| TCA 연결 문서의 `main` 예제 | 현재 잠긴 TCA는 1.26.2. 의존성 버전과 API 지원 여부를 별도로 확인 |

차이는 숨기거나 원문을 덮어써서 해결하지 않습니다. 영향받는 구현 작업에서는 팀의 선택을 확인하고,
합의된 변경을 Notion과 해당 Skill에 함께 반영합니다. 이 목록 자체는 새 팀 정책이 아닙니다.

## 에이전트 지원과 검증

Agent Skills의 `SKILL.md` + `name`·`description` frontmatter 구조를 사용합니다.
모델 이름이나 모델 API만으로 규칙 파일 자동 탐색을 보장하지 않습니다.

| 실행 방식 | 현재 확인 범위 | 사용 방법 |
| --- | --- | --- |
| 이 작업의 Codex 에이전트 | 명시적 파일 읽기·규칙 적용 시나리오를 검증. 아래 기록 참조 | 루트 AGENTS와 해당 SKILL을 직접 지정 |
| 새 Codex 세션의 자동 탐색 | 미검증. 이 세션에서 만든 파일을 읽는 것과 구분 | 새 작업을 저장소 루트에서 시작하고 자동 로드·선택 여부 확인 |
| Claude Code·Copilot·기타 에이전트 | 실행 환경이 없어 자동 탐색·계층 규칙 적용 미검증 | 먼저 아래 수동 참조 요청 사용, 제품별 지원은 실제 실행 후 기록 |

자동 탐색을 지원하지 않거나 확인되지 않았다면 다음처럼 요청합니다.

> 저장소 루트 AGENTS.md를 먼저 읽고 작업에 해당하는 .agents/skills/*/SKILL.md를 선택해 읽어 주세요.
> 읽은 Skill 경로, 선택한 검증과 그 결과 또는 생략/미실행 이유를 알려 주세요.

이 수동 참조 방식은 별도의 adapter 없이 사용할 수 있습니다.
나중에 특정 도구에 adapter가 필요해지면 그 도구에서 동작을 확인한 뒤
공통 파일 경로만 연결하는 얇은 참조를 검토합니다. 규칙 본문을 복사하지 않습니다.

### 반복 가능한 시나리오

새 에이전트 세션이나 규칙 변경 후 아래 요청을 사용합니다.
검증 시에는 파일을 실제 수정할지 읽기 전용으로 판단만 할지 명시하고 사용자 변경을 보존합니다.

| 개발 요청 | 기대하는 선택·행동 |
| --- | --- |
| README 오타 수정 | verify-change의 문서 전용 기준; native build/lint 생략과 이유 보고 |
| iPhone Feature 상태 로직 수정 | architecture·code-style·verify-change; iPhone 빌드·SwiftLint |
| 공유 Watch 메시지 필드 변경 | architecture·code-style·verify-change; 양쪽 송수신 확인·양쪽 빌드·SwiftLint |
| `.swiftlint.yml`만 수정 | verify-change; SwiftLint 실행, 앱 빌드는 필수 아님 |
| 리소스/프로젝트/의존성 변경 | verify-change; 영향 대상 빌드. Swift 변경도 있다면 lint 추가 |
| Linux에서 Swift 변경 검증 | 필요한 검사 선택 후 Xcode/SwiftLint 부재를 미실행으로 보고; 성공으로 표시하지 않음 |
| PR 작성·리뷰 | git-workflow·verify-change; 실제 템플릿·제목 형식·팀 리뷰 기준 확인 |
| Swift 스타일 설명만 요청 | code-style; 변경 없이 검사·빌드를 강제하지 않음 |

### 이번 작업의 검증 기록

- 기준: `develop`의 `cdf7e5e3c451c85e1448bc644598432e2cdd7925`, Linux x86_64.
- 변경 범위: Rules·Skills·관리 문서와 선택적 문서 검사 스크립트. Swift·앱 프로젝트·CI 변경 없음.
- 2026-10-26, 이 작업의 Codex 세션 및 별도 읽기 전용 에이전트 검토:
  루트 AGENTS와 필요한 Skill을 명시적으로 읽고 실제 개발 요청에 적용했습니다.
  자동 탐색 검증이나 앱 동작 테스트는 아닙니다.
- `bash .agents/skills/verify-change/scripts/check_agent_docs.sh` 통과.
  임시 사본에서 정상 입력 2건(현재 문서·1024자 한글 설명)과 잘못된 입력 8건(description 누락·빈 block scalar·null·길이 초과,
  이름 불일치, 절차 절 누락, 깨진 로컬 링크, Skill 인덱스 누락)을 검사해 정상은 exit 0,
  잘못된 입력은 모두 exit 1로 구분했습니다. 임시 사본은 제거했습니다.
  Linux의 Bash 5.2에서 실행했으며, macOS·Bash 3.2에서의 실제 실행은 미검증입니다.
- `git diff --check` 통과. 원문 SHA-256 두 개를 재대조했고 일치했습니다.
- 실개발 시나리오 결과:

  | 확인한 요청·실제 파일 | 관찰한 규칙 적용 |
  | --- | --- |
  | WatchPairingFeature 상태/effect 리뷰; View·iOS Client·요청/응답·observer 구현 추적 | architecture·code-style·verify-change 선택. iPhone만 수정할 경우 iPhone 빌드와 lint를 선택하고, lifecycle 취소·지연 응답 상태를 수동 검토 |
  | WatchBatteryMessage 필드 추가 설계; 공유 메시지·Watch responder·iPhone decoder 추적 | 같은 세 Skill 선택. 송수신 양쪽·request ID 유지를 확인하고 공유 코드 변경이므로 양쪽 빌드와 lint를 선택. payload 응답을 저장 완료로 혼동하지 않음 |
  | README 오타·lint 설정만 변경·PR 작성 요청 분류 | 각각 문서 검사/native 생략, lint만 필수, git-workflow·verify-change와 실제 PR 템플릿 사용으로 구분 |

  위 코드 리뷰·설계 검증은 읽기 전용으로 수행했고 앱 소스는 수정하지 않았습니다.
  네이티브 명령은 선택 결과이며 실행·통과 결과가 아닙니다.
- native build·SwiftLint는 문서 작업 기준에 따라 생략합니다.
  이 머신에는 Xcode·Swift·SwiftLint가 없어 Swift 변경 작업의 검사도 실행할 수 없습니다.
- Watch 빌드 명령은 실제 공유 스킴에서 도출한 로컬 검증 명령입니다.
  macOS에서의 실행 성공·앱 실행·기기 연동까지 검증한 것으로 해석하지 않습니다.

## 규칙을 수정하는 방법

1. Notion의 최신 내용과 이번 출처 표를 비교합니다. 새 export를 받았다면 파일 SHA-256도 비교하되,
   관측일·자동 생성 링크만 달라진 것인지 규칙의 의미가 달라진 것인지 본문을 확인합니다.
2. 항상 필요한 원칙은 AGENTS, 작업별 절차는 해당 Skill, 출처·차이·지원 현황은 이 가이드에 반영합니다.
   새로운 작업군이 생기기 전에는 Skill을 나누거나 추가하지 않습니다.
3. 같은 규칙을 여러 문서에 복사하지 않고 상대 링크로 연결합니다.
   Skill은 사용 시점·팀 규칙·절차·주의사항과 예외·결과 검증을 포함합니다.
4. 이 저장소의 metadata 관례는 `name`·`description` 두 필드이며 모두 plain single-line 값입니다.
   `name`은 폴더와 같은 소문자·숫자·하이픈(최대 64자), `description`은 선택 조건을 담은 1–1024자입니다.
   형식을 확장한다면 아래 보조 검사도 함께 갱신합니다.
5. 문서 검사와 관련 시나리오를 실행합니다. 도구별 자동 인식을 확인했다면
   도구·버전·날짜·실행 방식·관찰 결과를 남깁니다. 수동 로딩 성공을 자동 탐색 성공으로 기록하지 않습니다.
6. 새 실행 기준·규칙 변경은 팀과 확인하고 Notion도 갱신합니다.
   [git-workflow](../.agents/skills/git-workflow/SKILL.md)에 따라 PR을 준비합니다.

```sh
# 저장소 루트, Bash 3.2 이상과 macOS·Linux 기본 명령. 별도 패키지 불필요.
bash .agents/skills/verify-change/scripts/check_agent_docs.sh
git diff --check
```

보조 검사는 name·description 필수 항목, 필수 절, AGENTS의 Skill 링크와 단순 상대 파일 링크를 확인합니다.
일반 YAML/Agent Skills 전체 명세, URL 인코딩된 링크·앵커·외부 URL 응답·Notion 동기화·자동 탐색·규칙 준수는 검사하지 않습니다.
규칙 변경 PR에서는 위 시나리오와 원문 대조도 함께 검토합니다.

참고 규격: [Agent Skills specification](https://agentskills.io/specification),
[Codex Skills](https://developers.openai.com/codex/skills/),
[Codex AGENTS.md](https://developers.openai.com/codex/guides/agents-md/).
이번 환경에서는 이 공식 사이트의 본문 조회가 403으로 제한되어 제품별 지원을 추가로 단정하지 않았습니다.
