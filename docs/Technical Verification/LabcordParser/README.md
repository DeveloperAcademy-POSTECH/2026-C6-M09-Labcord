# Labcord Parser

문서·이미지에서 본문, 표, 그림 OCR을 읽는 온디바이스 파서입니다.
앱 코드는 [Researchers/Services/DocumentParsing](../../../Researchers/Services/DocumentParsing/)에 있습니다.
이 폴더에는 사용법, 검증 보고서, 측정값과 재현 도구를 모았습니다.

## 먼저 볼 자료

| 필요한 내용 | 문서 |
| --- | --- |
| API와 형식별 지원·제약 | [파싱 API 안내](Guides/Document-Parsing-Support.md) |
| Swift 예제를 실제로 실행한 결과 | [사용 예제 검증](Reports/Usage/API-Usage-Verification.md) |
| 형식별 샘플과 출처 | [외부 코퍼스](Reports/Corpus/Real-World-Corpus.md) |
| 실기기 시간·메모리 비교 | [최대 메모리 분석](Reports/Performance/Batch/Memory-Peak-Optimization.md) |
| 개발 컨벤션 확인·수정 | [컨벤션 검토](Reports/Review/Convention-Review.md) |

## 폴더 구조

```text
LabcordParser/
├── README.md
├── Guides/                  API·지원 범위, 업로드 안내
├── Reports/
│   ├── Usage/               Swift 사용 예제 결과
│   ├── Corpus/              외부 원본·HWP 비교
│   ├── OCR/                 숫자·대비·리샘플링 비교 수치
│   ├── Performance/
│   │   ├── Baseline/        실기기·시뮬레이터 기본 측정, 취소
│   │   ├── PDF/             PDF 병렬·단계별 시간
│   │   └── Batch/           대용량·혼합 배치·메모리 비교
│   └── Review/              코드·컨벤션·회귀 검토 기록
├── Tools/                   샘플 생성·검증·측정 집계 스크립트
├── Benchmarks/              기준 소스 해시와 복원 패치
└── ThirdPartyFixtures/      외부 샘플 출처·라이선스·NOTICE
```

보고서와 대응하는 수치 JSON은 같은 폴더에 뒀습니다. 기존 검증 과정과 실패 기록도 남겨뒀으니
수치를 비교할 때는 각 보고서의 기기·설정·기준 버전을 같이 확인하면 됩니다.

## 앱에서 사용하기

같은 `Researchers` 타깃에서 호출합니다. 별도 패키지 import는 필요 없습니다.

```swift
import Foundation

func parseDocument(at url: URL) async throws -> DocumentParseResult {
  try await DocumentParser.parse(.url(url))
}

func parseDocuments(_ urls: [URL]) async throws -> [DocumentBatchResult] {
  try await DocumentParser.parseBatch(urls.map(DocumentInput.url))
}
```

URL은 로컬 파일만 받습니다. Data·CGImage 입력도 지원합니다.
`fullText`에 OCR 텍스트가 포함되고, `blocks`·`images`·`warnings`에서 구조·그림·부분 실패를 확인할 수 있습니다.
배치 반환값은 입력 순서이며 항목마다 성공·실패가 따로 남습니다.

지원 형식은 TXT·CSV·JSON·XML, JPEG·PNG·HEIC·TIFF, PDF, DOCX·XLSX·PPTX,
DOC·XLS·PPT, HWP·HWPX, RTF·HTML·Markdown입니다.
형식을 읽을 수 있어도 모든 표·그림·앵커가 완전히 복원되는 것은 아닙니다.
옵션·진행 상태·취소와 형식별 제한은 [API 안내](Guides/Document-Parsing-Support.md)를 참고하면 됩니다.

## 도구 실행

명령은 저장소 루트에서 실행합니다. 경로에 공백이 있어 따옴표가 필요합니다.

```sh
python3 "docs/Technical Verification/LabcordParser/Tools/verify_real_world_corpus.py"
python3 "docs/Technical Verification/LabcordParser/Tools/summarize_benchmark.py" --help
python3 "docs/Technical Verification/LabcordParser/Tools/prepare_before_benchmark.py" --help
```

실기기·시뮬레이터 테스트 명령은 [사용 예제 검증](Reports/Usage/API-Usage-Verification.md)과
각 성능 보고서에 있습니다. 테스트 원본은 [ResearchersTests/Fixtures](../../../ResearchersTests/Fixtures/),
샘플 출처와 고지는 [ThirdPartyFixtures](ThirdPartyFixtures/README.md)에서 확인할 수 있습니다.
