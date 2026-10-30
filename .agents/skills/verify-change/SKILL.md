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
5. [문서 갱신 절차](../../../docs/agent-rules/maintenance.md#구현-변경에-따른-문서-갱신)에 따라 변경이 관련 문서에 반영됐는지 확인합니다.
6. 결과와 최종 diff를 확인합니다. 기능 변경은 빌드 외에 아래 동작 검증을 적용합니다.
7. CI를 보고할 때는 실행 대상 저장소·이벤트·PR head SHA·대상 브랜치를 확인합니다.
   PR 이벤트의 merge ref 검사와 head 직접 검사를 구분하고 현재 head와의 연결을 확인합니다.
   이전 커밋이나 다른 대상 브랜치의 성공을 현재 PR의 성공으로 보고하지 않습니다.
   워크플로·job 조건과 실제 실행 기록을 함께 보고 성공·실패·조건부 생략·미실행을 구분합니다.
   실행 중·대기·취소 상태도 그대로 남기고, 로컬 결과를 CI 실행 증거로 대신하지 않습니다.

### 동작 검증과 범위

[architecture](../architecture/SKILL.md)의 상태·Effect 설계에 맞춰 변경한 동작의 시나리오를 선택합니다.

- Effect 취소·화면 종료 후 Observer·Task·Stream이 정리되는지, 콜백 순서가 보존되는지 확인합니다.
- 빠른 연속 입력·배타 동작의 중복 시작·응답 순서 역전·취소 뒤 늦은 응답을 확인합니다.
- 실패·권한 거부 뒤 상태 표시와 재시도·설정 변경 후 복귀 등 사용자 복구 경로를 확인합니다.

기존 테스트로 확인할 수 있는 부분은 해당 테스트를 수정·실행하고, 런타임 확인이 필요한 부분은
시뮬레이터/기기에서 확인합니다. 검증 수단마다 입증한 범위와 확인하지 못한 동작을 구분합니다.
새 테스트 타깃·검증용 자산·자동화를 추가하기 전에는 기존 수단으로 충분한지, 변경에 필요한지와
유지보수 책임·실행 환경을 확인합니다. 요청 범위를 넓히는 추가는 사용자·팀과 합의합니다.
요청 범위 안의 기존 테스트 수정·실행에 매번 별도 허가를 요구하지 않습니다.

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

1. 변경한 설명을 실제 구현·설정 및 팀 규칙과 대조합니다.
2. 상대 파일 링크와 앵커가 유효한지, 이동·삭제한 파일의 참조가 남아 있지 않은지 확인합니다.
   Skill을 바꿨다면 `name`·`description`, 필수 절과 AGENTS의 Skill 연결도 확인합니다.
3. 아래 명령으로 공백 오류를 확인하고, 관련 선택 시나리오는
   [관리 가이드](../../../docs/agent-rules/maintenance.md#에이전트-지원과-검증)를 참고합니다.

```sh
git diff --check
```

## 주의사항과 예외

- Linux에 Swift를 설치해도 SwiftUI·WatchConnectivity 등 Apple SDK를 제공할 수 없습니다.
  도구·SDK 부재로 필요한 검증을 못 했다면 “미실행”으로 기록합니다.
- 문서 전용 변경의 불필요한 native 검사는 “생략”입니다. 도구 부재와 혼동하지 않습니다.
- 현재 package와 공유 스킴에는 테스트 타깃이 없습니다. 0개 테스트를 실행하고 테스트 통과로 보고하지 않습니다.
  새 테스트가 추가되면 실제 대상·실행 개수·결과를 확인합니다.
- 검사 통과를 위해 규칙을 끄거나, 잠금 파일·최소 도구 버전을 낮추거나, 무관한 코드를 수정하지 않습니다.
- Watch 연동 변경은 빌드만으로 통신·저장 성공이 입증되지 않습니다. 연결·재전송·저장 확인 동작을 별도로 확인합니다.

## 결과 검증

사용자에게 전달하는 작업 완료 응답에는 변경 종류, 선택한 대상, 실행한 명령과 결과,
생략/미실행 항목과 이유, 작성자가 마무리할 사항을 포함합니다. 실행 실패·도구 부재·정책상 생략을 구분합니다.
네이티브 검사가 필요한데 실행할 수 없다면 다음 실행 환경과 명령을 남기고 통과로 표시하지 않습니다.
PR 본문의 구성과 기본 체크리스트는 [git-workflow](../git-workflow/SKILL.md)를 따릅니다.
완료 응답의 전체 실행 기록을 본문에 복사하도록 요구하거나 리뷰어에게 재검증을 맡기지 않습니다.
