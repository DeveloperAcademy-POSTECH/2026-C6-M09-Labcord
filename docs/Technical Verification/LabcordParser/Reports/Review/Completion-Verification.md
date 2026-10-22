# 남은 형식 지원 보완과 검증 기록

최신 외부 코퍼스 검증은 [외부 문서·이미지 코퍼스 기록](../Corpus/Real-World-Corpus.md)에 있다.
20개 형식별 3개 원본을 추가한 뒤 전체 XCTest 65개가 통과했다. 아래는 기존 자체 생성
샘플 중심의 보완 이력이다.

2026-10-21, `hellosunghyun/feat-21-document-parsing`의 실제 checkout에서 작업했다.
최소 iOS 27.0과 Swift 언어 모드 5.0을 유지했고 새 앱 패키지는 추가하지 않았다.
검증 환경은 Xcode 27.1(27A9275), iOS 27.1 SDK, iOS 27.0의 iPhone 17 시뮬레이터이다.

## 완료한 구현

| 대상 | 보완 내용 | 실제 검증 |
| --- | --- | --- |
| DOC | CFB 파트 판별, Word piece table·셀/행 구분, OfficeArt PNG/JPEG 경로 | LibreOffice가 만든 바이너리 DOC에서 본문·표 셀·이미지 OCR·PNG 반환 |
| XLS | BIFF 셀과 DrawingGroup·CONTINUE 내장 그림 추출 | 바이너리 XLS의 본문 값·표 셀·이미지 OCR·PNG 반환 |
| PPT | 현재 UserEdit·persist directory의 슬라이드만 선택, 그룹 셀 표 추출 | 바이너리 PPT의 본문·표 셀·그림, 마스터 기본 문구 제외 |
| HWP | 기존 파서에 PNG 반환과 이미지 자원 제한 추가 | 직접 생성한 HWP 5.0.2.2 압축·비압축 CFB 양쪽의 본문·표·BinData OCR·PNG |
| TIFF | 프레임별 ImageIO 디코딩·방향·Vision OCR, 순서·진행 이벤트 | 두 프레임, 90도 회전과 방향 태그, 한영 OCR, 중간 프레임 실패 후 앞뒤 결과 보존 |
| PDF 표 | 벡터 선분 그리드·병합 셀, 선 없는 반복 정렬 표 | 2×2 표, 병합 셀의 columnSpan, 선 없는 4×2 표, 본문/OCR 중복 제어 |
| PDF 이미지 | XObject·inline 이미지 위치 추적, PNG 래스터와 OCR | 페이지 내 좌표, 중첩 Form·Matrix·BBox, 페이지 90도 회전, 동일 그림의 반복 배치 |
| 자원·수명 | 페이지·프레임·이미지 검사 수·PNG 합계·PDF 연산 제한 | 부분 결과 보존, 혼합 배치 순서, 프레임 사이 취소, 임시 디렉터리 정리 |

PDF scanner·operator table·content stream은 C API의 소유권에 맞춰 `defer`로 해제한다.
이미지 검사 한도에는 PNG 보관에 성공한 그림뿐 아니라 실패한 시도도 포함한다.
커진 Office 순회 코드는 `DocumentOfficeParseContext.swift`로 분리했다.

## 검증 결과

전체 XCTest **41개가 실패 없이 통과**했다. CI와 같은 앱 빌드와 엄격 SwiftLint도 통과했다.
C 객체 해제를 마지막으로 보완한 뒤 PDF·이미지·자원 관련 **12개 회귀 테스트도 실패 없이 통과**했다.

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' \
  -parallel-testing-enabled NO

xcodebuild build -project Researchers.xcodeproj -scheme Researchers \
  -destination 'generic/platform=iOS Simulator'

swiftlint lint --strict
```

최초 전체 검증의 결과 번들은 `/tmp/issue21-completion-acceptance.xcresult`이다.
자원 해제 보완 후 결과 번들은 `/tmp/issue21-pdf-lifetime.xcresult`이다.
이 임시 경로의 산출물은 저장소에 포함하지 않는다.

## 관측한 시간

전체 41개 테스트의 XCTest 보고 시간은 **19.304초**였다. 다음 값은 같은 실행의
테스트 케이스 벽시계 시간이며, 순수 파서 벤치마크나 기기별 보장치가 아니다.
자산 읽기·생성·assertion 및 HWP의 엄격 읽기 검증을 포함한다.

| 케이스 | 시간 |
| --- | ---: |
| DOC 본문·표·그림 | 0.890초 |
| XLS 본문·표·그림 | 0.535초 |
| PPT 본문·표·그림 | 0.551초 |
| 압축·비압축 HWP 두 파일 | 2.219초 |
| TIFF 두 프레임·회전 | 0.930초 |
| TIFF 중간 프레임 자원 실패 | 1.093초 |
| PDF 표와 내장 이미지 위치 | 1.034초 |
| PDF 중첩 Form·페이지 회전 | 0.381초 |

## 지원 수준과 한계

- 구형 Office는 실제 바이너리 경로로 검증했다. Word의 복잡한 병합·중첩 표,
  모든 역사적 버전, 내장 벡터 그림의 모든 변형까지 보장하는 코퍼스는 아니다.
- PPT 그룹 표와 구형 그림의 인라인 순서·앵커가 불완전하면 문서 파트/스트림 위치와
  경고를 반환한다. 알 수 없는 픽셀 좌표를 임의로 만들지 않는다.
- HWP 샘플은 외부 문서를 가져온 것이 아니라 레코드와 CFB를 직접 생성한 것이다.
  Hancom 편집기에서 생성된 모든 버전·컨트롤의 호환성을 검증한 것은 아니다.
- 선 없는 PDF 표는 정렬에 따른 추론이며 위치가 있는 경고를 반환한다.
  스캔·이미지 속 표는 요청 범위대로 OCR 텍스트까지 제공하고 셀 구조를 복원하지 않는다.
- PDF PNG는 표시 영역의 래스터이다. 원본 압축 이미지와 바이트가 같지 않으며,
  겹친 요소나 복잡한 클립의 실제 윤곽과 사각 경계가 다를 수 있다.
- 실기기는 연결하지 않아 기기별 처리 시간·최대 메모리·장시간 실행은 측정하지 못했다.
  동기 네이티브 호출을 강제 중단하지 않으며 단계 경계에서 취소를 확인한다.
- 기존 MIT·MPL·LGPL 라이선스 구성은 유지한다. 배포 고지·소스 제공·재링크 조건을
  충족했다는 배포 승인이나 법률 검토를 이번 코드 검증으로 대신하지 않는다.

자산 출처와 재생성 절차는 [검증 자산 안내](../../../../../ResearchersTests/Fixtures/README.md)에 있다.
구현에 참고한 공개 API·형식 문서는 [Apple CGPDFScanner](https://developer.apple.com/documentation/coregraphics/cgpdfscanner),
[CGPDFContentStream](https://developer.apple.com/documentation/coregraphics/cgpdfcontentstream),
[Microsoft PPT persist directory](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/5bda8009-6612-4679-a6eb-6fb83cbcf195),
[Office Drawing](https://learn.microsoft.com/openspecs/office_file_formats/ms-odraw/)이다.
