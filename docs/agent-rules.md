# Agent Rules·Skills 관리 가이드

팀 협업 규칙을 에이전트에 적용하는 방법과 Rules·Skills의 관리 절차를 안내합니다.

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
docs/agent-rules.md                     적용 기준·인식 검증·관리 방법
```

가까운 협업 절차인 Git·PR은 하나의 Skill에서 관리합니다.
참고자료와 템플릿은 기존 파일·공식 문서 링크를 재사용하며, 필요한 경우에만 `references/`나 `assets/`를 추가합니다.
에이전트를 쓰지 않는 팀원은 기존 Xcode·Git 작업을 그대로 할 수 있습니다.
이 파일들은 hook·자동 실행·패키지 설치·CI 변경을 추가하지 않습니다.

## 팀 규칙의 적용 위치

| 규칙 | 관리 위치 |
| --- | --- |
| 브랜치·커밋·이슈·PR | git-workflow: 이름·제목·템플릿 |
| Git·코드 리뷰 | git-workflow: Git Flow·CodeRabbit·팀원 승인 |
| Swift 스타일 | code-style: 이름·레이아웃·로컬 lint 설정 |
| Feature와 모듈 | architecture: View/Feature 역할·내부 참조 제한·모듈 경계 |
| 저장과 전송 | architecture: iPhone 저장·Watch 전송·완료 상태·중복 방지 |
| 공통 코드와 디자인 | architecture: 공통화 시점·UI 책임·패키지 연결 |
| 변경별 검증 | verify-change: 빌드·SwiftLint 실행·생략·결과 보고 |
| 공통 원칙 | AGENTS.md; 명령·상세 절차는 Skill로 분리 |

현재 의존성은 [Package.resolved](../Researchers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved),
모듈 구성은 [Package.swift](../Packages/ResearchersModules/Package.swift)를 확인합니다.

## 현재 구현과 적용 기준

| 항목 | 현재 설정·적용 |
| --- | --- |
| Watch 앱 경로 | 소스는 `ResearchWatchApp/`, 스킴은 `ResearchWatch Watch App` |
| 로컬 패키지 | 단일 `Packages/ResearchersModules/Package.swift` 아래 네 개 타깃 |
| 기기별 저장·통신 | 기기별 구현은 `LabcordiOS`·`LabcordWatchOS`에도 있음. 새 저장 구현의 경로는 해당 작업에서 팀과 확인 |
| SwiftData | `LabcordShared/Models`의 모델 선언과 iPhone의 저장 실행 책임을 구분. Watch에 저장 구현을 새로 두거나 기존 모델을 자동 이동하지 않음 |
| 들여쓰기 | 스타일 가이드는 2 spaces, 기존 Swift는 주로 4 spaces. 적용 기준은 팀 확인 사항이며 일괄 포맷 변경하지 않음 |
| import 배치 | 스타일 가이드와 기존 코드 배치에 차이가 있음. `.swiftlint.yml`의 `sorted_imports`도 확인하며 새 우선순위를 임의 확정하지 않음 |
| 줄 길이 | warning 99·error 150이고 `--strict`는 warning도 실패 처리 |
| 도구·SDK | Package의 iOS/watchOS 최소 26, 프로젝트 배포 대상 27.0, CI runner `xcode-27`, Swift tools 6.4 |
| TCA API | 잠긴 버전은 1.26.2. 사용하는 API의 지원 여부를 확인 |

현재 경로·버전·설정 등 확인 가능한 사실은 실제 저장소와 일치하도록 유지합니다.
기존 팀 규칙과 충돌하는 동작이나 새 정책의 결정이 필요하면 팀에 확인합니다.
단순한 경로·버전 갱신을 위해 별도 승인을 반복해서 요청하지 않습니다.

## 구현 변경에 따른 문서 갱신

에이전트는 작업을 완료하기 전에 변경한 구현·설정과 관련 문서를 대조하고,
영향받는 설명을 같은 작업·PR에서 함께 수정합니다. 파일 이동·삭제로 더 이상 맞지 않는 설명과 링크도 정리합니다.

| 변경 | 먼저 확인할 실제 구현·설정 | 갱신 대상 |
| --- | --- | --- |
| 경로·모듈·타깃·스킴 | 디렉터리, `Package.swift`, Xcode 프로젝트·공유 스킴 | AGENTS 저장소 지도, architecture, 이 가이드의 현재 구현 표, 관련 링크 |
| Swift·SDK·의존성 버전 | `Package.swift`, Xcode 빌드 설정, `Package.resolved`, CI | verify-change 전제 조건, 이 가이드의 현재 구현 표 |
| 빌드·테스트·lint·CI 절차 | 워크플로, `.swiftlint.yml`, 스킴, 실제 테스트 타깃·실행 명령 | verify-change 명령·대상·검사 기준, code-style 설정 설명, 관련 사용 안내 |
| Feature·저장·통신 책임 | 관련 Feature·Client·공유 모델·메시지와 모듈 의존성 | architecture, 이 가이드의 적용 기준 |
| Skill·템플릿·협업 절차 | Skill metadata·파일, 실제 템플릿, 합의된 협업 규칙 | AGENTS의 Skill 안내, 관련 Skill, 이 가이드의 구조·사용 방법 |

1. 변경한 파일·설정명·기존 경로·이전 버전을 검색해 오래된 설명이 남아 있는지 확인합니다.
   이 가이드의 표뿐 아니라 AGENTS·Skills·README 등 관련 문서 전체를 대상으로 합니다.
2. 확인 가능한 사실은 실제 구현·설정에 맞춰 직접 갱신합니다.
   문서를 맞추려고 무관한 구현을 바꾸거나, 구현의 우연한 차이를 새 팀 규칙으로 만들지 않습니다.
3. 같은 내용을 여러 문서에 복제하기보다 담당 문서 한 곳과 참조 링크를 갱신합니다.
4. 바뀐 명령·링크를 확인하고 관련 검증을 수행합니다. 실행할 수 없는 검증은 그 이유를 보고합니다.

이 절차는 에이전트가 수행하는 작업의 완료 조건입니다. 다른 사람이 코드만 수정했을 때
문서가 저절로 바뀌는 상시 감시·자동 동기화 기능은 아닙니다. 문서 검사기는 형식·링크만 검사하므로
구현과 설명이 의미상 일치하는지도 에이전트가 확인해야 합니다.

## 에이전트 지원과 검증

Agent Skills의 `SKILL.md` + `name`·`description` frontmatter 구조를 사용합니다.
모델 이름이나 모델 API만으로 규칙 파일 자동 탐색을 보장하지 않습니다.

자동 탐색과 지침 적용 범위는 사용하는 도구·설정에 따라 확인합니다.
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

## 규칙을 수정하는 방법

1. 구현·설정 변경에 따른 갱신은 [문서 갱신 절차](#구현-변경에-따른-문서-갱신)를 따릅니다.
   팀 규칙 자체를 바꾸는 경우에는 합의와 적용 범위를 확인합니다.
2. 항상 필요한 원칙은 AGENTS, 작업별 절차는 해당 Skill, 적용 기준·지원 현황은 이 가이드에 반영합니다.
   새로운 작업군이 생기기 전에는 Skill을 나누거나 추가하지 않습니다.
3. 같은 규칙을 여러 문서에 복사하지 않고 상대 링크로 연결합니다.
   Skill은 사용 시점·팀 규칙·절차·주의사항과 예외·결과 검증을 포함합니다.
4. 이 저장소의 metadata 관례는 `name`·`description` 두 필드이며 모두 plain single-line 값입니다.
   `name`은 폴더와 같은 소문자·숫자·하이픈(최대 64자), `description`은 선택 조건을 담은 1–1024자입니다.
   형식을 확장한다면 아래 보조 검사도 함께 갱신합니다.
5. 문서 검사와 관련 시나리오를 실행합니다. 도구별 자동 인식과 지침 적용 범위를 확인하되,
   파일을 직접 읽는 방식과 자동 탐색을 구분합니다.
6. 새 실행 기준·규칙 변경은 팀과 확인한 뒤 관련 문서에 일관되게 반영합니다.
   [git-workflow](../.agents/skills/git-workflow/SKILL.md)에 따라 PR을 준비합니다.

```sh
# 저장소 루트, Bash 3.2 이상과 macOS·Linux 기본 명령. 별도 패키지 불필요.
bash .agents/skills/verify-change/scripts/check_agent_docs.sh
git diff --check
```

보조 검사는 name·description 필수 항목, 필수 절, AGENTS의 Skill 링크와 단순 상대 파일 링크를 확인합니다.
일반 YAML/Agent Skills 전체 명세, URL 인코딩된 링크·앵커·외부 URL 응답·자동 탐색·규칙 준수는 검사하지 않습니다.
규칙 변경 PR에서는 위 시나리오와 팀 규칙의 적용 범위도 함께 검토합니다.
