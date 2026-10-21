# Issue #21 업로드 구성

## 포함

| 목적 | 경로 | 내용 |
| --- | --- | --- |
| 앱 기능·빌드 설정 | `Researchers/Services/DocumentParsing/`, `Researchers.xcodeproj/`의 관련 변경 | 파싱·OCR API, 형식별 구현, 승인된 의존성, 테스트 타깃·공유 scheme |
| 회귀·재현 | `ResearchersTests/`, `scripts/DocumentParsing/` | 자체 생성 샘플, 외부 20형식 각 3개·대용량 PDF 3개, 테스트·계측·재현 도구 |
| 샘플 고지 | `ThirdPartyFixtures/` | 포함한 외부 샘플의 라이선스·NOTICE·출처 |
| 지원·검증 기록 | 이 폴더의 API 안내·검증 보고서·수치 JSON·`Benchmarks/` | 실제 지원과 제약, 과거 실패·후보 비교, 최종 실기기 수치, 기준 소스 해시·복원 패치 |

외부 원본은 테스트 재현에 필요한 공개 샘플이며 출처와 고지를 함께 보존한다.
연구·학습용 개인 문서나 새 모델 가중치는 포함하지 않는다. 가장 큰 샘플은 약 32MB다.
자산은 테스트 타깃에서 사용하며 앱의 파싱 동작에서 다운로드하지 않는다.

## 로컬에 보존하고 제외

- 이슈 작성용 `GitHub-Issue-Drafts.md`
- 로컬 작업 경로와 지시문이 담긴 `Implementation-Prompt.md`
- 게시 본문을 준비하는 `PR-21-Draft.md`
- `/tmp` 아래 원본 xcresult·Instruments trace·빌드 로그·별도 기준 프로젝트
- DerivedData·서명 키·프로비저닝 프로파일·로컬 도구 캐시

앞의 세 Markdown 파일은 삭제하거나 이동하지 않고 커밋 대상에서만 제외한다.
`.gitignore`나 CI·린트 규칙을 완화하지 않는다.

## 커밋 구성

1. `feat: 온디바이스 문서 파싱과 OCR 구현` — 앱 코드·의존성·프로젝트 설정
2. `test: 문서 파싱 회귀 검사와 재현 자산 추가` — 테스트·샘플·도구·출처 고지
3. `docs: 문서 파싱 지원 범위와 실기기 검증 기록` — API·지원·제약·검증 수치

## 게시 기준

`hellosunghyun/feat-21-document-parsing`에서 `develop`을 대상으로 Draft PR을 생성한다.
연결 이슈는 #21이며, 합의한 지원 범위와 현재 이슈 본문의 차이가 있어 자동 종료 문구를
사용하지 않는다. 린트·빌드·실기기 결과와 완료하지 못한 복원 범위를 구분해 기록한다.
