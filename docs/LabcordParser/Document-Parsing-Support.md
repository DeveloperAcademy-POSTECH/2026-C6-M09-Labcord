# 문서 파싱 API와 지원 범위

구현은 `Researchers/Services/DocumentParsing/`에 있으며 `Researchers` iOS 타깃 내부에서
동작한다. 최소 iOS 27.0과 Swift 언어 모드 5.0을 유지한다. 문서와 OCR 이미지를
서버로 전송하지 않으며, 외부 참조 이미지는 자동 다운로드하지 않는다.

## 폴더 구성

`Researchers/Services/DocumentParsing/`의 코드는 역할별로 나눈다.

| 폴더 | 역할 |
| --- | --- |
| Core | 파싱 API, 형식 판별, ZIP 검증, CFB 접근 |
| Models | 입력·결과·위치·경고·내장 이미지 모델 |
| Text | 일반 텍스트, 구조화 텍스트, HTML·Markdown, 참조 이미지 |
| Images | 이미지 디코딩·인코딩, 다중 프레임 처리, Vision OCR |
| PDF | 페이지·좌표·연산자 검사, 표·이미지 추출 |
| Office | Office 백엔드와 구형 DOC·XLS·PPT 보완 처리 |
| HWP | HWP·HWPX 처리 |

하위 폴더는 다음과 같다. 각 형식의 진입 파서는 해당 형식 폴더에 둔다.

```text
DocumentParsing/
├── Core/
│   ├── Containers/
│   └── Detection/
├── Models/
├── Text/
│   ├── Markup/
│   └── Structured/
├── Images/
│   ├── Codec/
│   └── OCR/
├── PDF/
│   ├── Pages/
│   ├── Scanning/
│   └── Extraction/
│       ├── Tables/
│       └── Images/
├── Office/
│   ├── Backend/
│   └── Legacy/
│       ├── Word/
│       ├── PowerPoint/
│       └── Images/
└── HWP/
```

관련 테스트는 `ResearchersTests/DocumentParsing/` 아래 Core·Text·Images·PDF·Containers로
나눈다. Swift 샘플 생성 도우미는 `ResearchersTests/Support/` 아래
Containers·Images·PDF로 나누며, 검증 자산과
생성 스크립트가 사용하는 `ResearchersTests/Fixtures/` 경로는 유지한다.
Xcode의 파일 시스템 동기화 그룹이 하위 Swift 파일을 타깃에 자동 반영한다.

## API

- `DocumentParser.parse(_:options:progress:)`: 로컬 파일 URL, 파일명 힌트가 있는 Data,
  방향 정보가 있는 CGImage를 처리한다. ZIP·CFB는 컨테이너 구조로 판별한다.
- `DocumentParser.parseBatch(_:options:progress:)`: 입력 순서에 따라 문서별 성공·실패를
  반환하며, 동시에 처리하는 문서 수를 제한한다. 전체 배치 취소는 호출자에게 전파한다.
- `DocumentParseResult`: `fullText`, 순번이 정규화된 `blocks`, 위치가 있는 `warnings`,
  추출한 PNG `images`를 반환한다. 전체 텍스트는 텍스트 블록만 조합한다.
- `DocumentEmbeddedImage`: `id`, `pngData`, `orientation`, `location`을 제공한다.
  PDF는 페이지에 실제 표시된 이미지 영역의 래스터를 반환한다. 원본 JPEG/압축 스트림을
  그대로 반환하는 API는 아니다. Office·HWP의 지원되는 내장 그림도 PNG로 반환한다.
- `DocumentLocation`: `part`, 1부터 시작하는 `page`·`row`·`column`, 문단 번호,
  `rowSpan`·`columnSpan`, 좌상단 기준 정규화된 `bounds`를 제공한다.
  PDF 좌표는 페이지 회전을 반영한 MediaBox 기준이며, TIFF의 page는 프레임 번호이다.
  구형 Office·HWP에서 기하 앵커를 얻지 못하면 스트림·파트 위치와 경고를 반환한다.
- 진행 이벤트는 입력 인덱스와 `identifying`, `extracting`, `recognizingText`, `completed`,
  `failed`, `cancelled` 단계를 포함한다.

## 형식별 실제 지원

| 형식 | 구현 | 제약 |
| --- | --- | --- |
| TXT | 인코딩 판별과 문단 | 레거시 인코딩은 휴리스틱 |
| CSV | 인용 필드, 이스케이프 따옴표, CRLF·CR·LF, 행·셀 위치 | 수식 계산 제외 |
| JSON·XML | 값·요소 텍스트와 경로 | JSON 객체 순서와 XML 혼합 콘텐츠 표현은 단순화 |
| JPEG·PNG·HEIC | Vision 한영 OCR, 방향, 위치·제공 가능한 신뢰도 | 시스템 OCR 품질에 따름 |
| TIFF | 다중 프레임 OCR, 프레임별 방향·순서, 부분 실패 후 다른 프레임 보존 | 설정한 프레임·픽셀 한계 적용 |
| PDF | 본문·페이지, 선 기반 표와 병합 셀, 반복 정렬로 추론한 선 없는 표, 내장 이미지 PNG·위치·OCR | 표 추론과 복잡한 레이아웃에는 위치 기반 경고 |
| DOCX·XLSX·PPTX | 백엔드 문서 트리, 본문·표·셀·시트·슬라이드, 지원되는 내장 이미지 PNG·OCR | 헤더·푸터·각주·복잡한 그림 앵커는 백엔드 노출 범위에 따름 |
| DOC | 백엔드 텍스트, Word 97 계열 piece table와 셀·행 구분, OfficeArt 그림 | 복잡한 병합·중첩 표와 그림의 인라인 순서는 완전 복원하지 않음 |
| XLS | BIFF 셀·행·열, DrawingGroup와 CONTINUE의 OfficeArt 그림 | 그림의 셀 앵커와 모든 Excel 서식은 복원하지 않음 |
| PPT | 현재 편집본의 슬라이드, 그룹 셀의 표, 지원되는 내장 그림 | 그룹 표와 다른 요소의 인라인 순서는 경고로 표시 |
| HWP·HWPX | 문단·표·위치, 압축·비압축 HWP, BinData PNG·OCR | 미지원 컨트롤과 기하 앵커 누락은 경고 |
| RTF | Foundation 본문 텍스트 | RTF 고유 표 구조·그림 복원은 제한적 |
| HTML | SwiftSoup 본문·목록·표, 내장·로컬 이미지 OCR | CSS 레이아웃 렌더링 제외, 원격 이미지 건너뜀 |
| Markdown | 제목·본문·빈 셀을 보존하는 파이프 표, 로컬·내장 이미지 OCR | 방언과 복잡한 구문은 제한적 |
| ODF·EPUB·SVG·EMF·WMF | 합의된 지원 범위 밖 | 지원 완료로 표시하지 않음 |

이미지 속 표와 스캔 PDF의 표는 OCR 텍스트까지만 추출하며 셀 구조를 복원하지 않는다.
PDF 이미지 위치는 `q/Q`, 변환 행렬, 반복 배치, 중첩 Form과 Form BBox, 사각 클립을
추적한다. 곡선 클립·패턴·임의 회전 등의 복잡한 경우에는 표시 영역의 사각 경계가
정확한 이미지 윤곽과 다를 수 있다. 선 없는 표는 정렬된 3행 이상을 추론하며,
`uncertainReadingOrder` 경고를 함께 반환한다.

## 자원과 수명

기본 제한은 입력 100 MiB, 선언된 해제 크기 및 보관 이미지 합계 500 MiB,
압축·CFB 항목 10,000개, 이미지·페이지 래스터 4천만 픽셀, 동시 문서 2개이다.
`maximumDocumentPages`는 PDF·TIFF에서 1,000개, `maximumEmbeddedImages`는 128개,
`maximumPDFOperators`는 검사 대상 PDF 연산 100,000개가 기본값이다.

PDF Form 깊이는 16, 표 선분은 2,000개, 그리드 후보는 1,024개 교차 좌표 조합,
선 없는 표의 문자 검사는 100,000자로 제한한다. 제한에 걸린 위치를 경고로 반환한다.
ZIP 경로 탈출·중복·암호화 컨테이너를 검사하고, 원본 URL의 보안 접근은 파싱 종료까지
유지한다. Office 임시 디렉터리는 성공·실패·취소로 함수가 종료될 때 정리한다.

취소는 단계·페이지·프레임·이미지 경계와 Vision 호출 전후에서 확인한다.
실행 중인 동기 서드파티 호출을 강제 종료하지는 않는다.

## 의존성

기존 승인된 SwiftSoup 2.14.3(MIT), OpenDocument.core 7.5.2(MPL 2.0),
hwp-swift 0.19.0(LGPL 2.1), 기존 전이 의존성 OLEKit 0.3.1(MIT)을 사용한다.
이번 보완으로 새로운 앱 패키지를 추가하지 않았다. 배포 시 기존 라이선스의 고지,
소스 제공·재링크 등 적용 조건은 별도로 준수해야 한다.

## 검증

20개 파일 형식별 외부 원본 3개씩을 사용하는 테스트는
[외부 코퍼스 검증](Real-World-Corpus.md)에 별도로 기록한다.

생성 방법과 자산 출처는 [검증 자산 안내](../../ResearchersTests/Fixtures/README.md),
실제 검증 결과는 [보완 검증 기록](Completion-Verification.md)에 있다.

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' \
  -parallel-testing-enabled NO
xcodebuild build -project Researchers.xcodeproj -scheme Researchers \
  -destination 'generic/platform=iOS Simulator'
swiftlint lint --strict
```

## HWP 앵커·설명과 숫자 OCR 보완

- HWP/HWPX의 표 셀은 `rowSpan`·`columnSpan`을 반환한다.
- 그림은 원본 문단·표 셀에서 순회하며 논리적 위치를 보존한다. 표의 `part`에 문단과
  표 컨트롤 경로를 포함해 서로 다른 표의 동일 행·열을 구분한다.
- 내장 이미지의 `sourceDescription`은 원본 그림 설명이며 OCR 결과가 아니다.
  `.image` 블록에도 설명을 남기되 `fullText`에는 합치지 않는다.
- 동일 BinData를 여러 번 참조하면 이미지 배치 블록은 유지하고 비트맵·OCR은 재사용한다.
  앵커가 없는 그림은 뒤에서 추출하고 위치가 있는 경고를 남긴다.
- 부동 그림의 실제 페이지 조판·정규화 페이지 bounds는 여전히 확정하지 않는다.
  문단·셀 위치를 페이지 좌표인 것처럼 반환하지 않으며 읽기 순서 경고를 유지한다.
- CoreHwp가 보존하지 않는 HWPX 그림 설명은 검증된 ZIP의 원본 XML에서 보완한다.
  ZIP 해제 출력·CRC·로컬 헤더·경로를 검사하고 XML 외부 엔티티·DTD를 거부한다.
  새 패키지 없이 시스템 zlib를 사용하며 임시 파일에 패키지를 풀지 않는다.
- 작은 이미지(100만 픽셀 이하)에서 신뢰도 0.65 이하·글자 높이 24픽셀 이하인 특정
  숫자 패턴은 밝기 임계값 150/140/160의 픽셀 투영으로 최대 세 번 더 Vision 인식한다. 두 번째 인식이 `$`를
  반환하고 나머지 숫자·구분자가 동일하며 신뢰도가 낮아지지 않은 경우만 채택한다.
  원본 문자열은 `DocumentBlock.ocrOriginalText`에 보존한다. 문자열 치환으로
  `$`를 만들어 내지 않으며 모든 숫자 오류를 보정한다는 보장은 없다.
- 성능·오류 재현과 실기기 실행 상태는 [잔여 보완 검증](Remainder-Verification.md)을 따른다.

실제 iPhone 17의 최종 88개 테스트·측정값과 임시 서명 방식은
[실기기 검증](Physical-Device-Verification.md)에 기록했다. 저장소 서명 설정은 변경하지 않았다.

## PDF 병렬 처리와 단계별 시간

PDFKit/CGPDF 문서·페이지·연산자 검사·표 추출·렌더링·PNG 보존 예산은 문서별 한 작업이
페이지 순서대로 처리한다. 준비된 불변 CGImage의 OCR은 TaskGroup으로 병렬 처리한다.
PDF 객체·CGContext·가변 픽셀 버퍼는 병렬 작업으로 전달하지 않는다.
전체 페이지 인식 범위와 삽입 이미지 OCR을 유지한다. 같은 페이지 래스터 전체와 정확히 같은
크기·영역의 그림을 이미 OCR에 성공했다면 페이지 OCR 결과로 재사용한다. 첫 인식 실패나
부분 그림은 기존 전체 페이지 OCR을 수행한다. 해상도나 읽는 페이지를 줄이지 않는다.

```swift
var options = DocumentParserOptions()
options.maximumConcurrentPDFPages = 4
options.pdfWorkingMemoryTargetBytes = 256 * 1024 * 1024
let result = try await DocumentParser.parse(.url(localURL), options: options)
let metrics = result.metrics
```

- 기본 작업창은 활성 CPU 수다. 실제 상한은 요청값·CPU 수·페이지 수·추정 작업 메모리로 제한한다.
- 작업 메모리 목표는 기본 256MiB이며 RGBA 래스터와 임시 작업 여유를 추정한다.
  완료 결과의 PNG·PDFKit/Vision 내부 메모리를 포함한 프로세스 전체의 강제 상한은 아니다.
  RGBA 작업량 외에 OCR 작업당 단일 문서 32MiB, 배치 48MiB의 예약 여유를 둔다.
- 한 페이지 자체가 목표보다 크면 단독 처리한다. 목표 때문에 OCR·해상도를 생략하지 않는다.
- 배치에서는 호출 하나가 공용 PDF 작업 예산을 소유한다. PDF 준비·OCR 전체의 진행 페이지 수를
  요청 작업창·활성 CPU 수 이하로 유지하고, 여유가 생기면 FIFO 대기 중인 다른 PDF가 사용한다.
  문서 수로 작업창을 고정 분할하지 않는다. 추정 작업 바이트도 배치 전체가 공유한다.
  독립적인 여러 parse 호출의 전역 상한을 제공하는 설정은 아니다.
- 이미지 개수·보존 바이트는 준비 단계에서 원본 페이지 순서대로 차감한다.
  maximumPDFImageBytes는 PDF 그림 PNG의 문서별 보존 바이트 한도다. 기본값 500MiB로 기존
  동작을 유지하며 maximumExpandedBytes와 둘 중 작은 값을 적용한다. 더 작은 한도를 지정하면
  이후 그림은 위치 경고를 남기고 보존하지 않는다. 전체 페이지 OCR은 계속 수행한다.
- 불투명한 8비트 sRGB/DeviceRGB 그림의 실제 색이 256개 이하면 정확한 팔레트 PNG로
  인코딩한다. 양자화·해상도 변경은 없다. 다색·투명·그 밖의 그림이나 인코딩 실패는 기존
  PNG 인코더로 처리한다. Display P3 등 광색역도 기존 인코더로 처리한다. PNG 바이트는
  달라질 수 있으나 위치·OCR 입력은 바꾸지 않는다.
  OCR 완료 순서가 바뀌어도 이미지 선택·전체 텍스트·블록 정렬을 원본 순서로 조합한다.
- 취소 시 TaskGroup 자식에도 전파하고 OCR 호출 전후에 확인한다. 동기 Vision 호출 내부를
  즉시 중단한다는 보장은 없다. 페이지·이미지의 복구 가능한 오류는 경고와 부분 결과로 유지한다.

PDF 결과의 metrics에는 PDF 처리 경과 시간, 최대 진행 중 페이지 수, 추정 작업 메모리와
단계별 timings가 있다. 각 항목은 stage·page·startOffsetSeconds·seconds를 제공한다.
다른 형식은 현재 metrics가 nil이다. 배치 PDF에는 batchScheduling도 포함되며 전체 배치의
최대 진행 페이지 수·추정 작업 바이트와 종료 시 activePages·waitingRequests를 제공한다.
정상 완료 시 두 종료 수치는 0이다. 시간·수치만 반환하며 문서 내용을 로그에 남기지 않는다.

| 단계 | 측정 범위 |
| --- | --- |
| pdfOpen | PDF 열기·암호화·페이지 수 확인 |
| pdfScan | PDF 연산자와 그림 배치 검사 |
| pdfTables | 선 기반 표·정렬 기반 표 분석 |
| pdfNativeText | 원본 텍스트 줄·위치 추출 |
| pdfRender | 기존 해상도의 페이지 래스터 생성 |
| pdfImages | 그림 영역 crop·PNG 인코딩·예산 확인 |
| pdfImageOCR | 각 내장 그림 OCR과 위치 변환 |
| pdfPageOCR | 페이지 전체 OCR과 중복 제거 |
| pdfPageOCRReuse | 동일한 전체 페이지 그림의 성공한 OCR을 재사용 |
| pdfAssembly | 페이지 순서·블록·전체 텍스트 조합 |
| pdfAwait | 부모 작업이 병렬 완료를 기다린 구간 |
| pdfSchedule | 배치 공용 작업 예산을 기다린 구간 |

병렬 페이지 시간은 겹치므로 단계 합계가 경과 시간보다 클 수 있다. pdfAwait도 자식 OCR과
겹치는 부모 대기 시간이다. 단계 합계를 서로 더해 전체 실행 시간으로 해석하지 않는다.
측정값·성능 비교·검증 명령은 [PDF 병렬 검증](PDF-Parallel-Verification.md)에 기록한다.

실제 204쪽 스캔 원본·42쪽 래스터 전용 입력·7개 혼합 배치의 실기기 검증은
[대용량 스캔·배치 검증](Large-Scan-Batch-Verification.md)에 별도로 기록한다.

공용 작업 예산·PNG 메모리 개선과 한국어 실제 스캔 검증의 최신 상태는
[배치·메모리·한국어 검증](Batch-Memory-Korean-Verification.md)을 따른다.

## OCR 수명과 최신 검증

`parse`·`parseBatch` 하나의 호출 범위에서만 Vision 세션을 재사용한다. 세션 상태를 각각
Mutex로 보호하고 유휴 세션은 최대 2개만 보관한다. 다른 세션의 OCR을 직렬화하지 않으며
실패·취소한 세션은 버린다. 호출이 끝나면 풀을 해제하며 전역 영구 캐시는 두지 않는다.

직전 실기기 버전과 결과 전체 지문을 비교한 최신 메모리 보완·110개 회귀 결과는
[최대 메모리 분석·개선](Memory-Peak-Optimization.md)을 따른다. 과거 보고서의 다른 실행
순서·기준 버전과 최신 수치를 섞어 개선율을 계산하지 않는다.
