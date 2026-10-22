# 개발 컨벤션 최종 검토

2026-10-22. Issue #21 파싱·OCR 변경 전체와 PR 메타데이터를 확인했다.
기준은 [팀 개발 컨벤션](https://sassy-cloth-fbe.notion.site/3fa06046c66e804eb90bcfb3d7341498),
저장소 README·SwiftLint·CI·PR 양식, 사용자의 명시 지시다.

## 규칙별 확인

| 항목 | 확인 및 조치 |
| --- | --- |
| 브랜치 | 팀의 종류/이슈번호-작업자 형식과 기존 Devin PR #11·#13을 확인하고 `feat/#21-Devin`으로 변경 |
| 커밋 | 기존 4개 메시지를 `종류/#21: 설명`으로 재작성. 메시지 재작성 직후 전체 Git tree와 로컬 제외 파일 해시 동일 확인 |
| PR | 기존 PR #11·#13·#20의 제목 형태를 따라 `feat/#21: iOS 온디바이스 문서 파싱 및 OCR 구현`, 대상 develop·Draft 유지 |
| 이슈 제목 | 이슈 #21은 종류: 설명 형태이며 이번 작업에서 변경하지 않음 |
| 구조 | 앱 내부의 독립 서비스와 형식별 경계를 유지. TCA 화면·Reducer 결합은 명시된 작업 범위 밖이므로 추가하지 않음 |
| Swift 스타일 | PR의 Swift 파일 86개와 기존 파일을 포함해 strict lint 실행, 100개 파일·위반 0개 |
| 로그·서식 | PDF 성능 테스트의 시작·종료 콘솔 출력 2개 제거. 측정 JSON attachment·assertion은 유지. 호출 인자 정렬과 불필요한 빈 줄 정리 |
| 설정 | iOS 27.0·Swift 언어 모드 5.0 유지. CI·린트 규칙·저장소 서명 설정 변경 없음 |
| 자료 | 문서·Tools는 Technical Verification 하위에 유지. 테스트 원본·라이선스 고지는 보존하고 로컬 작업 문서 3개는 계속 제외 |

Notion 본문에는 별도의 Swift 들여쓰기·헤더·MARK 세부 규칙이 없었다.
따라서 임의의 새 규칙이나 형식별 파서 구조 변경을 추가하지 않았다.
기존 브랜치를 사용하라는 앞선 지시보다 이후 사용자의 컨벤션 준수·브랜치 변경 지시를 반영했다.

## 이번 수정

- `DocumentPDFParallelPerformanceTests.swift`: 불필요한 콘솔 로그·빈 줄 제거와 인자 배치 정리.
- `Publication-Contents.md`: 커밋 메시지·최종 브랜치 표기 수정.
- Git 기록: 기존 4개 커밋 메시지에 #21 추가. 사용자 승인 후 이력 재작성과 브랜치 이름 변경.
- GitHub: 원본 브랜치 변경으로 닫히는 PR #26을 새 Draft PR에 연결하고 설명 코멘트를 이전.

앱 파서 45개 Swift 소스는 성능 측정에 사용한 해시와 같다. 테스트의 로그·서식만 변경했으며
새 기능·공개 API·의존성·메모리 옵션은 변경하지 않았다.

## 검증 결과

- iPhone 17 Release 일반 회귀 **110개 통과·실패 0개**, XCTest 19.665초.
- CI 기준 generic iOS Simulator 앱 빌드 성공.
- `swiftlint lint --strict`: **100개 파일·위반 0개**.
- 외부 원본 60개·20형식과 추가 대용량 PDF 3개 무결성 검증 통과.
- 이번 변경의 `git diff --check` 통과.

대용량·반복 성능 시나리오는 이번 스타일 검토에서 다시 실행하지 않았다.
이번 일반 회귀의 제외 목록·서명 실행 방식은 [최대 메모리 검증](../Performance/Batch/Memory-Peak-Optimization.md)의
최종 회귀 명령과 동일하다. 앱 소스가 같으므로 기존 시간·메모리 측정은 과거 실행 기록으로 보존한다.

실행 증거는 로컬 `/tmp/issue21-convention-final.xcresult`,
`/tmp/issue21-convention-final-tests.log`, `/tmp/issue21-convention-final-build.log`,
`/tmp/issue21-convention-lint-after.log`다. 로그·서명 자산은 커밋하지 않는다.
