---
name: architecture
description: Labcord에서 TCA Feature를 설계하거나 수정하고 모듈 경계, SwiftData 저장, iPhone과 Watch의 메시지 교환을 구현하거나 리뷰할 때 사용합니다.
---

# TCA와 기기별 책임

## 사용 시점

Feature 구성·화면 연결·의존성, 저장소, WatchConnectivity 또는 공유 코드를 변경·리뷰할 때 사용합니다.
단순 문서 오탈자 수정에는 적용하지 않습니다.

## 팀 규칙

- Swift·TCA·SwiftData를 사용합니다. 화면 또는 사용자 흐름을 기준으로 Feature를 구성합니다.
  화면 안의 컴포넌트도 독립 상태·Action·Effect가 모이면 하위 Feature 분리를 검토합니다.
  단순 표시 컴포넌트까지 모두 Feature로 만들거나 특정 루트 View 구조를 일괄 금지하지 않습니다.
- View는 상태 표시와 Action 전달을, Feature는 상태 변경과 동작 처리를 맡습니다.
- 다른 Feature의 내부 구현·전용 Components를 직접 참조하지 않고 부모 Feature에서 조합합니다.
  Swift는 폴더 단위 접근 제한을 제공하지 않으므로 가능한 파일 내부 구현에는 `private`을 적용합니다.
- 영구 저장은 iPhone이 담당합니다. Watch에 SwiftData 저장 구현을 새로 두지 않습니다.
- Watch는 입력을 iPhone으로 전송합니다. 요청·전송 완료·iPhone 저장 완료를 구분하고,
  저장 확인 전에 Watch에서 “저장 완료”를 표시하지 않습니다. 재전송 중복 방지에는 요청 식별자를 사용합니다.
- 코드는 먼저 사용하는 앱에 두고 실제로 양쪽에서 필요해질 때 공통화합니다.
  용도 불명확한 Utils·Clients를 만들지 않습니다.
- 디자인 값은 공통화하되 플랫폼별 UI 책임을 구분합니다. Lo-fi 단계에서는 시스템 기본 컴포넌트·
  폰트·SF Symbols로 사용자 흐름부터 확인하고, 별도 디자인 체계나 추상화를 미리 확장하지 않습니다.
  커스텀 UI는 검증할 요구와 단계에 맞춰 도입할 수 있습니다.
  별도 패키지·타깃 추가 시 manifest와 사용하는 앱의 의존성 연결을 함께 확인합니다.

## 절차

1. [현재 구현과 적용 기준](../../../docs/agent-rules/project-context.md#현재-구현과-적용-기준)을 보고 영향받는 기기를 식별합니다.
2. View·Feature·기기별 Client·공유 모델/메시지 중 어느 책임인지 정합니다.
   `Packages/ResearchersModules/Package.swift`와 관련 소스의 기존 구현을 먼저 확인합니다.
3. TCA 작업은 State·Action·Reducer와 의존성 경계를 확인합니다.
   참고 문서의 `main` API를 복사하기보다 잠긴 의존성 버전에서 지원하는 API인지 확인합니다.
   Effect의 시작·완료·취소 경로를 추적하고, 취소가 Observer 해제·내부 Task 취소·Stream 종료 등
   실제 자원 정리로 이어지는지 확인합니다. 콜백을 Action이나 비동기 스트림으로 옮길 때는
   원래 이벤트 순서가 보존되는지, 취소 뒤 늦게 도착한 이벤트가 상태를 바꾸지 않는지 확인합니다.
   연속 입력의 병합·취소 기준, 동시에 수행할 수 없는 동작의 배타성, 늦은 응답의 반영 조건을 정하고
   실패·권한 거부 뒤 사용자가 재시도하거나 설정을 바꾸고 흐름으로 돌아올 경로를 마련합니다.
4. 통신 형식 변경 시 `LabcordShared/Messages`, iPhone 송수신, Watch 송수신을 함께 추적합니다.
   재전송·연결 끊김·중복 요청·저장 실패 시 사용자가 보는 상태를 확인합니다.
5. [code-style](../code-style/SKILL.md)과 [verify-change](../verify-change/SKILL.md)를 함께 적용합니다.

## 주의사항과 예외

- 현재 소스 경로인 `ResearchWatchApp/`와 `Packages/ResearchersModules/Sources/`를
  이 Skill 적용만을 위해 임의로 옮기지 않습니다.
- 현재 `LabcordShared/Models`에는 SwiftData 모델 선언이 있습니다.
  선언 위치와 저장 실행 책임을 구분하고, 이 Skill 적용만을 위해 모델을 옮기지 않습니다.
- 새 Dependency나 TestStore 테스트는 변경 동작에 필요한 범위에서 도입합니다.
  테스트 타깃·자산·자동화 추가의 필요성과 유지보수 범위는 [verify-change](../verify-change/SKILL.md)를 따릅니다.
- 팀 규칙은 특정 TCA 매크로·파일 템플릿·동시성 모델을 새로 강제하지 않습니다.

## 결과 검증

Feature 간 내부 참조가 없는지, 모듈 의존성이 맞는지, 메시지 양 끝이 일치하는지 확인합니다.
비동기 수명·입력 처리·복구 경로를 변경했다면 [verify-change](../verify-change/SKILL.md)의 동작 검증을 적용합니다.
저장 완료 표시와 재전송 동작을 변경했다면 그 시나리오를 검증합니다.
검증한 기기·대상과 확인하지 못한 런타임 동작을 구분해 보고합니다.
