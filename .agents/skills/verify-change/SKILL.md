---
name: verify-change
description: Labcord 변경의 검증을 선택하고 실행하거나 결과를 보고할 때 사용합니다. Swift, SwiftLint 설정, 빌드 입력, 문서 변경을 구분하고 도구 부재를 명확히 보고합니다.
---

# 변경에 맞는 검증

## 사용 시점

변경 후 검증·완료 보고·PR 준비에 사용합니다. 읽기 전용 질의에는 변경 검사를 강제하지 않습니다.

## 팀 규칙

아래 기준은 [이슈 #32](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M09-Labcord/issues/32)의 실행 기준입니다.
여러 종류의 변경이 섞였으면 필요한 검증의 합집합을 수행합니다.

| 변경 | SwiftLint CLI | 앱 빌드 |
| --- | --- | --- |
| Swift 코드 | 실행 | 영향받는 대상 실행 |
| `.swiftlint.yml`만 변경 | 실행 | 필수 아님 |
| 프로젝트 설정·의존성·리소스 등 빌드 입력 | Swift 변경도 있으면 실행 | 영향받는 대상 실행 |
| 문서·협업 규칙만 변경 | 생략 가능 | 생략 가능 |

파일 확장자만 보지 않습니다. 예를 들어 문서와 함께 빌드 스크립트나 CI 명령을 바꿨다면
문서 전용 변경으로 취급하지 않고 실제 실행에 미치는 영향을 확인합니다.

## 절차

1. `git diff --name-status`, `git diff --cached --name-status`, `git ls-files --others --exclude-standard`로
   작업 중 변경·스테이징·새 파일을 확인합니다. PR 검증이라면 대상 브랜치와의 전체 diff도 확인합니다.
2. 수정 범위에 따라 대상을 선택합니다.
   - `Researchers/`, `LabcordiOS`: `Researchers`
   - `ResearchWatchApp/`, `LabcordWatchOS`: `ResearchWatch Watch App`
   - `LabcordShared`, `LabcordDesignSystem`, 공통 manifest·프로젝트 설정·의존성: 양쪽 앱
   - 실제 참조 관계가 더 넓으면 해당 대상도 포함합니다.
3. 저장소 루트에서 아래 명령을 실행합니다. 실행 직전 실제 CI·manifest·프로젝트 설정과 맞는지 확인합니다.
4. 실패는 원인을 확인하고 필요한 수정 후 재검증합니다. 출력을 저장할 때 원래 명령의 실패 상태를 보존합니다.
5. [문서 갱신 절차](../../../docs/agent-rules.md#구현-변경에-따른-문서-갱신)에 따라 변경이 관련 문서에 반영됐는지 확인합니다.
6. 결과와 최종 diff를 확인합니다. 기능 변경은 빌드 외에 관련 테스트나 시뮬레이터/기기 동작도 확인합니다.

### 명령과 전제 조건

작업 디렉터리는 `Researchers.xcodeproj`가 있는 저장소 루트입니다.
현재 `Package.swift`는 Swift tools 6.4, 프로젝트는 iOS/watchOS 27.0을 요구하고 CI는 `xcode-27`을 사용합니다.
macOS·호환 Xcode/SDK·시뮬레이터 런타임이 필요합니다.

```sh
xcodebuild -version
swift --version
xcodebuild -showsdks
swiftlint version

# SwiftLint: .github/workflows/swiftlint.yml의 검사 명령
swiftlint --strict

# iPhone: .github/workflows/build.yml의 빌드 명령
xcodebuild build \
  -project Researchers.xcodeproj \
  -scheme Researchers \
  -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation

# Watch: 별도 로컬 검사 후보 (현재 CI에 없으며 macOS 실행 미검증)
# 스킴이 iPhone 타깃도 포함하므로 지원 destination을 먼저 확인합니다.
xcodebuild -showdestinations \
  -project Researchers.xcodeproj \
  -scheme 'ResearchWatch Watch App'

# 아래 generic destination이 지원되는지 확인 후 실행합니다.
xcodebuild build \
  -project Researchers.xcodeproj \
  -scheme 'ResearchWatch Watch App' \
  -destination 'generic/platform=watchOS Simulator' \
  -skipMacroValidation
```

### Rules·Skills 문서 검사

문서만 변경했다면 링크·Skill metadata·팀 규칙 반영과 선택 시나리오를 확인합니다.
다음 Bash 보조 검사를 사용할 수 있습니다. macOS·Linux의 기본 명령만 사용하며 설치나 CI 연결은 필요하지 않습니다.

```sh
bash .agents/skills/verify-change/scripts/check_agent_docs.sh
git diff --check
```

이 스크립트는 저장소 문서 형식·로컬 링크만 검사합니다. 자동 Skill 인식이나 규칙 준수,
Swift 빌드·앱 동작을 검증하지 않습니다. 동작 시나리오는 [관리 가이드](../../../docs/agent-rules.md#에이전트-지원과-검증)를 봅니다.

## 주의사항과 예외

- Linux에 Swift를 설치해도 SwiftUI·WatchConnectivity 등 Apple SDK를 제공할 수 없습니다.
  도구·SDK 부재로 필요한 검증을 못 했다면 “미실행”으로 기록합니다.
- 문서 전용 변경의 불필요한 native 검사는 “생략”입니다. 도구 부재와 혼동하지 않습니다.
- 현재 package와 공유 스킴에는 테스트 타깃이 없습니다. 0개 테스트를 실행하고 테스트 통과로 보고하지 않습니다.
  새 테스트가 추가되면 실제 대상·실행 개수·결과를 확인합니다.
- 검사 통과를 위해 규칙을 끄거나, 잠금 파일·최소 도구 버전을 낮추거나, 무관한 코드를 수정하지 않습니다.
- Watch 연동 변경은 빌드만으로 통신·저장 성공이 입증되지 않습니다. 연결·재전송·저장 확인 동작을 별도로 확인합니다.

## 결과 검증

보고에는 변경 종류, 선택한 대상, 실행한 명령과 결과, 생략/미실행 항목과 이유,
남은 확인 사항을 포함합니다. 실행 실패·도구 부재·정책상 생략을 구분합니다.
네이티브 검사가 필요한데 실행할 수 없다면 다음 실행 환경과 명령을 남기고 통과로 표시하지 않습니다.
