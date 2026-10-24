# 문서 파싱 API

`DocumentParser`는 화면과 독립적으로 로컬 문서를 파싱한다. 이미지 추출과 OCR은 요청별로 선택하며 **둘 다 기본값은 false**다.

```swift
// 기본: PDF·Office·HWP 등의 네이티브 본문과 표만 읽는다.
let textResult = try await DocumentParser.parse(.url(fileURL))

// 그림 PNG와 OCR 텍스트까지 필요할 때 명시한다.
let result = try await DocumentParser.parse(
  .url(fileURL),
  options: .init(extractImages: true, performOCR: true)
)

// 두 설정은 독립적이다. PNG를 보관하지 않고 OCR만 수행할 수도 있다.
let ocrResult = try await DocumentParser.parse(
  .data(data, fileName: "document.pdf"),
  options: .init(performOCR: true)
)

let outcomes = try await DocumentParser.parseBatch(
  inputs,
  options: .init(extractImages: true, maximumConcurrentDocuments: 2)
)
```

| extractImages | performOCR | 처리 범위 |
| --- | --- | --- |
| false | false | 네이티브 본문·표. 그림 PNG 추출·PDF 래스터화·OCR 생략 |
| true | false | 네이티브 본문·표 + 제공 가능한 그림 PNG와 배치 블록 |
| false | true | 네이티브 본문·표 + 이미지·스캔 OCR. PNG 반환 생략 |
| true | true | 본문·표·PNG·OCR 모두 처리 |

- `images`는 추출한 PNG, `image` 블록은 그림 배치, `imageOCR` 블록은 인식 텍스트다. `fullText`에는 본문·제목·셀·OCR 텍스트만 들어간다.
- JPEG·PNG·HEIC·TIFF·CGImage 직접 입력도 같은 설정을 사용한다. 둘 다 false면 이미지의 텍스트·PNG 결과는 비어 있다. TIFF는 프레임별 위치·방향과 페이지 제한을 유지한다.
- 스캔 PDF는 네이티브 텍스트가 없으므로 본문을 읽으려면 `performOCR: true`가 필요하다. `extractImages`만 켜면 그림은 반환하지만 이미지 속 문자는 읽지 않는다.
- PDF·Office·HWP의 기존 그림 처리 경로와 HTML·Markdown의 내장·로컬 참조 그림에 적용한다. 이 옵션이 형식별 미지원 요소를 새로 지원하게 만드는 것은 아니다.
- HTML·Markdown 참조 그림은 본문 뒤에 추가하므로 순서 경고가 남을 수 있다. 외부 이미지 다운로드와 문서 업로드는 하지 않는다.
- 단일 입력과 혼합 배치 모두 `options`로 설정한다. 배치에서는 같은 설정이 모든 입력에 적용된다.
- 암호화·손상·압축·입력 크기 검사와 취소는 설정과 관계없이 적용한다. 그림·OCR을 켜면 해당 작업의 픽셀·개수·보관 바이트 제한도 적용한다.
- 기존 호출에서 이미지·OCR 결과가 필요했다면 두 옵션을 명시해야 한다. 결과를 필터링해서 숨기는 것이 아니라 해당 추출 작업을 생략한다.

## Office 추출 경로

- XLS·XLSX는 OpenDocument.core의 셀 좌표 API로 읽는다. HTML 화면용 행·열 눈금과 인쇄용 중복 출력을 본문에 섞지 않는다.
- 셀 주소와 제공 가능한 병합 범위를 보존한다. 희소 셀 조회는 문서 전체 100,000좌표까지 수행하며, 초과하면 이미 읽은 결과와 중단 위치의 `resourceLimitReached` 경고를 반환한다.
- DOC·PPT 본문과 표는 OfficeOxide 0.1.15로 읽는다. 단일 행·열 및 병합 PPT 표의 기존 판정 기준은 고정된 호환 패치로 유지한다.
- DOCX·PPTX는 OpenDocument.core를 사용한다. 구형 OfficeArt 내장 그림 복구는 기존 구현을 유지한다.
- 라이브러리 소스·라이선스·재빌드와 바이너리 해시는 저장소의 `ThirdParty/OfficeOxide/`에 있다. 앱·CI 빌드에서 Rust를 설치하거나 문서를 외부로 전송하지 않는다.
