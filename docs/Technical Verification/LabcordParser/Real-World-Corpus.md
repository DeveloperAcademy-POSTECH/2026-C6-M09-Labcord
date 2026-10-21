# 외부 문서·이미지 코퍼스 검증

## 구성

2026-10-21에 Aside CLI로 후보와 출처를 조사하고, 공개 업스트림의 고정 커밋에서
20개 파일 형식별 3개씩, 총 60개 원본(6,029,910바이트)을 확보했다.
출처는 Apache POI·Tika, libheif 예제, hwp-swift이다. 기존 자체 생성 샘플도 유지한다.

대출 계산·세율·도시 데이터, 보도자료, 업무 화면 캡처, 사진, 다중 페이지 이미지,
문서·슬라이드와 업스트림 회귀 샘플을 함께 사용한다. 일부 파일은 특정 형식 기능을
검사하기 위한 작은 회귀 샘플이다. 60개 전부를 실제 업무 문서로 수집한 코퍼스나
임의의 실제 사용자 문서에 대한 호환성 인증으로 해석하지 않는다.

별칭 JPG·TIF·MD는 각각 JPEG·TIFF·Markdown으로 센다. `CGImage` 직접 입력은
파일 형식이 아니므로 별도 3개를 수집하지 않는다. 기존 이미지 입력 테스트가 담당한다.

## 파일 목록

원본 파일과 SHA-256, 출처 URL, 커밋, 라이선스 근거, 기대 결과는
[manifest](../../../ResearchersTests/Fixtures/RealWorld/RealWorldManifest.json)에 기록했다.
파일은 수정·변환하지 않았고 Git blob 또는 원본 SHA-256과 대조했다.
라이선스·NOTICE·HWP별 생성 이력 사본은 [출처 고지](ThirdPartyFixtures/README.md)에 있다.

| 형식 | 원본 1 | 원본 2 | 원본 3 |
| --- | --- | --- | --- |
| CSV | [test-columnar.csv](../../../ResearchersTests/Fixtures/RealWorld/csv/real-csv-01-test-columnar.csv) | [poi-integration-exceptions.csv](../../../ResearchersTests/Fixtures/RealWorld/csv/real-csv-02-poi-integration-exceptions.csv) | [poi-integration-handlers.csv](../../../ResearchersTests/Fixtures/RealWorld/csv/real-csv-03-poi-integration-handlers.csv) |
| DOC | [SampleDoc.doc](../../../ResearchersTests/Fixtures/RealWorld/doc/real-doc-01-SampleDoc.doc) | [simple-table.doc](../../../ResearchersTests/Fixtures/RealWorld/doc/real-doc-02-simple-table.doc) | [pictures_escher.doc](../../../ResearchersTests/Fixtures/RealWorld/doc/real-doc-03-pictures_escher.doc) |
| DOCX | [SampleDoc.docx](../../../ResearchersTests/Fixtures/RealWorld/docx/real-docx-01-SampleDoc.docx) | [table_footnotes.docx](../../../ResearchersTests/Fixtures/RealWorld/docx/real-docx-02-table_footnotes.docx) | [VariousPictures.docx](../../../ResearchersTests/Fixtures/RealWorld/docx/real-docx-03-VariousPictures.docx) |
| HEIC | [IMG_1034.heic](../../../ResearchersTests/Fixtures/RealWorld/heic/real-heic-01-IMG_1034.heic) | [example.heic](../../../ResearchersTests/Fixtures/RealWorld/heic/real-heic-02-example.heic) | [testHEIF.heic](../../../ResearchersTests/Fixtures/RealWorld/heic/real-heic-03-testHEIF.heic) |
| HTML | [about.html](../../../ResearchersTests/Fixtures/RealWorld/html/real-html-01-about.html) | [testHTML_embedded_img.html](../../../ResearchersTests/Fixtures/RealWorld/html/real-html-02-testHTML_embedded_img.html) | [testHTML_charset_utf8.html](../../../ResearchersTests/Fixtures/RealWorld/html/real-html-03-testHTML_charset_utf8.html) |
| HWP | [real-hwp-01-noori.hwp](../../../ResearchersTests/Fixtures/RealWorld/hwp/real-hwp-01-noori.hwp) | [real-hwp-02-space-width.hwp](../../../ResearchersTests/Fixtures/RealWorld/hwp/real-hwp-02-space-width.hwp) | [real-hwp-03-gonggongnuri.hwp](../../../ResearchersTests/Fixtures/RealWorld/hwp/real-hwp-03-gonggongnuri.hwp) |
| HWPX | [real-hwpx-01-space-width.hwpx](../../../ResearchersTests/Fixtures/RealWorld/hwpx/real-hwpx-01-space-width.hwpx) | [real-hwpx-02-noori.hwpx](../../../ResearchersTests/Fixtures/RealWorld/hwpx/real-hwpx-02-noori.hwpx) | [real-hwpx-03-column.hwpx](../../../ResearchersTests/Fixtures/RealWorld/hwpx/real-hwpx-03-column.hwpx) |
| JPEG | [businessplan.jpg](../../../ResearchersTests/Fixtures/RealWorld/jpeg/real-jpeg-01-businessplan.jpg) | [timesheet.jpg](../../../ResearchersTests/Fixtures/RealWorld/jpeg/real-jpeg-02-timesheet.jpg) | [loancalc.jpg](../../../ResearchersTests/Fixtures/RealWorld/jpeg/real-jpeg-03-loancalc.jpg) |
| JSON | [config-template.json](../../../ResearchersTests/Fixtures/RealWorld/json/real-json-01-config-template.json) | [metadata-migration-3x-4x.json](../../../ResearchersTests/Fixtures/RealWorld/json/real-json-02-metadata-migration-3x-4x.json) | [file15_tags.json](../../../ResearchersTests/Fixtures/RealWorld/json/real-json-03-file15_tags.json) |
| MARKDOWN | [README.md](../../../ResearchersTests/Fixtures/RealWorld/markdown/real-markdown-01-README.md) | [README.md](../../../ResearchersTests/Fixtures/RealWorld/markdown/real-markdown-02-README.md) | [README.md](../../../ResearchersTests/Fixtures/RealWorld/markdown/real-markdown-03-README.md) |
| PDF | [testPDF.pdf](../../../ResearchersTests/Fixtures/RealWorld/pdf/real-pdf-01-testPDF.pdf) | [testOCR.pdf](../../../ResearchersTests/Fixtures/RealWorld/pdf/real-pdf-02-testOCR.pdf) | [testPDFTwoTextBoxes.pdf](../../../ResearchersTests/Fixtures/RealWorld/pdf/real-pdf-03-testPDFTwoTextBoxes.pdf) |
| PNG | [ss-features.png](../../../ResearchersTests/Fixtures/RealWorld/png/real-png-01-ss-features.png) | [baseball.png](../../../ResearchersTests/Fixtures/RealWorld/png/real-png-02-baseball.png) | [testRotated+10.png](../../../ResearchersTests/Fixtures/RealWorld/png/real-png-03-testRotated+10.png) |
| PPT | [SampleShow.ppt](../../../ResearchersTests/Fixtures/RealWorld/ppt/real-ppt-01-SampleShow.ppt) | [pictures.ppt](../../../ResearchersTests/Fixtures/RealWorld/ppt/real-ppt-02-pictures.ppt) | [WithMaster.ppt](../../../ResearchersTests/Fixtures/RealWorld/ppt/real-ppt-03-WithMaster.ppt) |
| PPTX | [SampleShow.pptx](../../../ResearchersTests/Fixtures/RealWorld/pptx/real-pptx-01-SampleShow.pptx) | [table-with-different-font-colors.pptx](../../../ResearchersTests/Fixtures/RealWorld/pptx/real-pptx-02-table-with-different-font-colors.pptx) | [WithMaster.pptx](../../../ResearchersTests/Fixtures/RealWorld/pptx/real-pptx-03-WithMaster.pptx) |
| RTF | [testRTFListMicrosoftWord.rtf](../../../ResearchersTests/Fixtures/RealWorld/rtf/real-rtf-01-testRTFListMicrosoftWord.rtf) | [testRTFJapanese.rtf](../../../ResearchersTests/Fixtures/RealWorld/rtf/real-rtf-02-testRTFJapanese.rtf) | [testRTFRegularImages.rtf](../../../ResearchersTests/Fixtures/RealWorld/rtf/real-rtf-03-testRTFRegularImages.rtf) |
| TIFF | [testTIFF.tif](../../../ResearchersTests/Fixtures/RealWorld/tiff/real-tiff-01-testTIFF.tif) | [testTIFF_multipage.tif](../../../ResearchersTests/Fixtures/RealWorld/tiff/real-tiff-02-testTIFF_multipage.tif) | [testtiff.tif](../../../ResearchersTests/Fixtures/RealWorld/tiff/real-tiff-03-testtiff.tif) |
| TXT | [CHANGES.txt](../../../ResearchersTests/Fixtures/RealWorld/txt/real-txt-01-CHANGES.txt) | [multi-language.txt](../../../ResearchersTests/Fixtures/RealWorld/txt/real-txt-02-multi-language.txt) | [comparison-report.txt](../../../ResearchersTests/Fixtures/RealWorld/txt/real-txt-03-comparison-report.txt) |
| XLS | [mortgage-calculation.xls](../../../ResearchersTests/Fixtures/RealWorld/xls/real-xls-01-mortgage-calculation.xls) | [sumifs.xls](../../../ResearchersTests/Fixtures/RealWorld/xls/real-xls-02-sumifs.xls) | [testEXCEL-charts.xls](../../../ResearchersTests/Fixtures/RealWorld/xls/real-xls-03-testEXCEL-charts.xls) |
| XLSX | [DataTableCities.xlsx](../../../ResearchersTests/Fixtures/RealWorld/xlsx/real-xlsx-01-DataTableCities.xlsx) | [AverageTaxRates.xlsx](../../../ResearchersTests/Fixtures/RealWorld/xlsx/real-xlsx-02-AverageTaxRates.xlsx) | [ExcelPivotTableSample.xlsx](../../../ResearchersTests/Fixtures/RealWorld/xlsx/real-xlsx-03-ExcelPivotTableSample.xlsx) |
| XML | [pom.xml](../../../ResearchersTests/Fixtures/RealWorld/xml/real-xml-01-pom.xml) | [pom.xml](../../../ResearchersTests/Fixtures/RealWorld/xml/real-xml-02-pom.xml) | [custom-mimetypes.xml](../../../ResearchersTests/Fixtures/RealWorld/xml/real-xml-03-custom-mimetypes.xml) |

## 테스트 방식

- `DocumentRealWorldCorpusTests`: 20개 형식별 테스트가 각각 3개 파일을 독립 처리한다.
- 코퍼스 검사는 형식 누락, 개수, 중복 ID·파일명·원본 해시, 출처·라이선스 필드를 검사한다.
- 파일별로 번들에서도 SHA-256을 확인한 뒤 공개 `DocumentParser.parse` API를 호출한다.
- 포맷, 기대 문구, 최소 본문·셀·이미지 수, 블록 읽기 순서와 전체 텍스트 일관성을 확인한다.
- 다중 TIFF는 두 프레임의 OCR 문구와 페이지 위치를 확인하고 스캔 PDF는 OCR 블록도 확인한다.
- 사진처럼 문자가 없는 파일은 디코딩·포맷 처리를 검사한다. 빈 OCR 결과가 문자 인식 품질을 증명하지는 않는다.
- 목록·표·이미지 등 구체적 기대값은 원본 XML·미리보기·생성 이력·독립 도구로 확인한 범위만 지정한다.
- 본문 원문을 첨부하지 않고 파일 ID·바이트 수·시간·문자 수·블록 수·이미지 수·경고 코드만 결과에 첨부한다.
- 원본 고정을 위해 RealWorld 폴더를 Xcode의 폴더 리소스로 복사한다. PNG 재압축으로 원본 해시가 바뀌는 일을 막는다.
- 테스트 코드는 번들 파일만 읽고 네트워크 호출을 하지 않는다. 외부 이미지 참조도 다운로드하지 않는다. 새 앱 의존성은 추가하지 않았다.

## 코퍼스로 발견하고 수정한 문제

1. HTML 주석으로 시작하는 Markdown의 XML 오인식을 수정했다.
2. BOM 없는 UTF-16의 판별을 NUL 분포로 제한하고 Windows-1252 문서를 임의의 UTF-16로 해석하던 문제를 수정했다.
3. HWP·HWPX의 고정폭·줄바꿈 방지 공백과 탭을 일반 텍스트에 보존한다.
4. OLEKit 0.3.1이 유효한 빈 MiniFAT의 ENDOFCHAIN을 거부하는 문제는 내부 읽기 사본의 미사용 포인터만 정규화한다. 원본 파일·실제 스트림을 변경하지 않는다.
5. 구형 Word의 WordDocument 스트림에 저장된 PNG BLIP을 그림 추출 대상으로 추가했다. 유효한 이미지 시그니처를 확인한 뒤에만 바이트를 복사한다.
6. 줄바꿈·공백이 있는 HTML 내장 이미지 base64를 처리하고, 잘못된 base64와 크기 초과 오류를 구분한다.
7. 그림만 있는 Office 문서에 본문이 없다는 이유로 추출 실패 경고를 붙이지 않는다.

기대값 자체의 오류도 바로잡았다. mortgage-calculation.xls의 실제 셀은 Principal·Rate·Term이며, 다른 스크린샷의 제목을 기대값으로 쓰지 않는다.
pictures.ppt는 원본의 현재 슬라이드 레코드를 검사했을 때 5장·본문 텍스트 레코드 0개·지원 비트맵 2개인 그림 전용 문서다. 이 파일은 이미지 보존을 검증한다.

## 실행 명령

```sh
python3 "docs/Technical Verification/LabcordParser/Tools/verify_real_world_corpus.py"
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/LabcordRealWorldTests.xcresult
xcodebuild build -project Researchers.xcodeproj -scheme Researchers \
  -destination 'generic/platform=iOS Simulator'
swiftlint lint --strict
```

`-resultBundlePath`는 존재하지 않는 경로를 지정한다. 실패 시 시뮬레이터 진단 수집이
장시간 대기한 실행이 있어 `-collect-test-diagnostics never`를 지정했다.
이 옵션은 테스트·assertion·xcresult 기록을 생략하지 않는다.

## 결과와 제약

- 원본 검증: 20개 형식 × 3개, 총 60개·6,029,910바이트. 해시·수량·중복 검사 통과.
- 전체 XCTest: **65개 통과, 실패 0건**, XCTest 실행 24.754초.
- 외부 코퍼스 전용 XCTest: **21개 통과**, 실행 12.809초. 20개 테스트에서 60개 원본을 처리하고 1개 테스트에서 코퍼스 구성을 검사한다.
- 인코딩·Markdown 신규 회귀 테스트: 3개 통과. 기존 41개 테스트도 통과.
- CI 명령 그대로 실행한 앱 빌드 성공. `swiftlint lint --strict`: 64개 파일, 위반 0건.
- 환경: Xcode 27.1(27A9275), iPhone 17 시뮬레이터, iOS 27.0. iOS 최소 버전과 Swift 언어 모드는 변경하지 않았다.
- 최종 xcresult: `/tmp/issue21-real-corpus-delivery.xgSC9k/Tests.xcresult`.
- 최종 테스트 로그: `/tmp/issue21-real-corpus-delivery.xgSC9k/test.log`.
- 빌드·린트 로그: `/tmp/issue21-real-corpus-delivery-build.log`, `/tmp/issue21-real-corpus-delivery-lint.log`.

파일별 측정값은 [측정 JSON](Real-World-Corpus-Metrics.json)에 있다. 아래는 문서 API 호출
직전부터 반환까지의 벽시계 시간 합계이다. 3개 샘플의 단일 시뮬레이터 실행으로,
형식 간 보편적인 성능 우열이나 실기기 성능을 뜻하지 않는다.

| 형식 | 파일 수 | API 시간 합계 ms | 가장 긴 파일 ms | 반환 블록 합계 | 반환 이미지 합계 |
| --- | --- | --- | --- | --- | --- |
| CSV | 3 | 10.2 | 8.9 | 3772 | 0 |
| DOC | 3 | 181.4 | 176.0 | 24 | 2 |
| DOCX | 3 | 273.7 | 270.6 | 12 | 2 |
| HEIC | 3 | 1600.0 | 917.9 | 0 | 0 |
| HTML | 3 | 97.9 | 96.6 | 4 | 0 |
| HWP | 3 | 1133.9 | 956.4 | 74 | 5 |
| HWPX | 3 | 972.8 | 954.7 | 75 | 4 |
| JPEG | 3 | 2062.5 | 941.4 | 157 | 0 |
| JSON | 3 | 3.4 | 1.7 | 585 | 0 |
| MARKDOWN | 3 | 10.8 | 9.0 | 312 | 0 |
| PDF | 3 | 2073.5 | 844.8 | 24 | 1 |
| PNG | 3 | 2639.0 | 1713.6 | 137 | 0 |
| PPT | 3 | 196.2 | 191.5 | 11 | 2 |
| PPTX | 3 | 7.5 | 3.6 | 45 | 0 |
| RTF | 3 | 46.9 | 25.5 | 33 | 0 |
| TIFF | 3 | 1179.7 | 821.0 | 10 | 0 |
| TXT | 3 | 18.2 | 16.6 | 3381 | 0 |
| XLS | 3 | 59.2 | 44.6 | 656 | 0 |
| XLSX | 3 | 119.7 | 87.9 | 3240 | 0 |
| XML | 3 | 3.6 | 2.2 | 230 | 0 |

60개 파일의 API 시간 합계는 12.690초이다.

경고는 시험 실패와 별도로 보존했다. HWPX 3개에서 `unsupportedElement` 269건,
DOCX VariousPictures의 미지원 그림 형식에서 `imageOCRFailed` 3건, 원격 참조 이미지
건너뛰기 6건, 읽기 순서 불확실성 8건이 기록됐다. 각 파일의 본문·표·지원 그림 기대값은
통과했으나, 이 결과는 경고 대상까지 완전히 추출했다는 뜻은 아니다.

최초 실행은 62개 테스트에서 12개 assertion이 실패했다. 원본 PNG의 Xcode 재압축,
포맷 판별·인코딩·특수 공백·빈 MiniFAT·Word 그림 경로 문제와 기대값 오류를 수정한 뒤
검증했다. 최종 실행은 실패 진단 수집을 끄고 정상적으로 xcresult까지 생성했다.

실기기 최대 메모리·OCR 정확도 점수·문서 전체의 모든 요소에 대한 정답 비교는 별도 측정 대상이다.
RTF는 본문 기대값을 검사하며, 이 테스트가 RTF 내장 이미지 복원을 보장하지 않는다.
한글 보도자료와 영어 문서·화면 OCR을 포함하되, 모든 형식에 한영 혼합 OCR 정답이 있는 것은 아니다.

## 후속 정답·OCR 검증

원본 기반 부분 정답 추가, 누리 HWP/HWPX 대조, 금액 OCR 측정과 최신 72개 테스트 결과는
[후속 품질 검증](Quality-Followup-Verification.md)을 따른다. 위 65개 실행은 이전 기준 결과다.
실기기 검증 조건은 [성능·취소 계획](Device-Performance-Plan.md)에 정리했다.
