---
name: code-style
description: Labcord의 Swift 코드를 작성하거나 수정하고 스타일을 리뷰할 때 사용합니다. SwiftLint 검사 선택과 실행은 verify-change를 함께 참조합니다.
---

# Swift 코드 스타일

## 사용 시점

Swift 코드 작성·수정·스타일 리뷰에 사용합니다. 문서만 수정하는 작업에는 적용하지 않습니다.

## 팀 규칙

팀이 연결한 [StyleShare Swift Style Guide](https://github.com/StyleShare/swift-style-guide)를 따릅니다.
명시되지 않은 API 이름은 [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)를 참고합니다.

- 타입·프로토콜은 UpperCamelCase, 함수·변수·상수·enum case는 lowerCamelCase를 사용합니다.
  불필요한 접두사와 `get`을 피하고, 약어 표기는 가이드의 해당 절을 확인합니다.
- 콜론 오른쪽 공백, 빈 줄의 공백 제거, 파일 끝 개행을 지킵니다.
  긴 선언·호출은 인자 단위로 나누고, 관련 코드 구분은 `// MARK:`, 문서 주석은 `///`를 사용합니다.
- 클로저의 추론 가능한 타입을 생략하고 유일한 마지막 클로저는 trailing closure로 표현합니다.
  컬렉션은 `[T]`, `[Key: Value]` 표기를 사용하고, 상속하지 않는 클래스는 `final`로 선언합니다.
- 명시적 `self`, extension을 통한 프로토콜 구현 분리 등 세부 규칙은 가이드의 해당 절을 확인합니다.
- 설명 주석을 늘리기 전에 의도가 드러나는 이름과 책임 구조로 표현할 수 있는지 확인합니다.
  코드만으로 알 수 없는 설계 제약·선택 이유는 필요한 곳에 간결한 주석으로 남기고 변경 시 함께 갱신합니다.

## 절차

1. 변경 파일과 주변 코드를 읽고 [현재 구현과 적용 기준](../../../docs/agent-rules/project-context.md#현재-구현과-적용-기준)을 확인합니다.
2. 스타일 수정과 동작 변경을 구분하고 관련 없는 파일의 포맷을 함께 바꾸지 않습니다.
3. `.swiftlint.yml`의 실제 설정을 읽습니다. 현재 `empty_count`, `first_where`,
   `sorted_imports`, `trailing_closure`, `closure_spacing`이 opt-in이며,
   줄 길이 warning 99·error 150입니다. `--strict`에서는 warning도 실패합니다.
4. 변경 후 [verify-change](../verify-change/SKILL.md)에서 검사·빌드 대상을 선택합니다.

## 주의사항과 예외

- StyleShare의 2 spaces·내장/외부 import 구분과 기존 파일의 4 spaces·import 배치에는 차이가 있습니다.
  이를 해결한다는 이유로 전체 포맷이나 SwiftLint 설정을 바꾸지 않습니다.
  해당 선택이 필요한 작업에서는 차이를 알리고 팀의 적용 기준을 확인합니다.
- SwiftLint가 통과해도 이름·책임 분리 등 모든 스타일 규칙이 검증된 것은 아닙니다.
- 참고 가이드가 언급하는 Then 등의 라이브러리를 스타일 적용만을 위해 추가하지 않습니다.
- 검사 목적으로 `swiftlint --fix`나 자동 커밋·push를 실행하지 않습니다.

## 결과 검증

변경 diff에 관련 없는 포맷 수정이 없는지 확인하고, 수동으로 확인한 스타일 항목과
SwiftLint 결과를 구분해 보고합니다. 스타일 규칙과 기존 코드 사이에 판단이 필요한 차이가 있으면 남깁니다.
