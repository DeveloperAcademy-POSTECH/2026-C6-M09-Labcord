# Swift API 사용 예제 실기기 검증

2026-10-22, iPhone 17 / iOS 27.0.1(24A446), Release.
PR 코멘트의 `DocumentParser.parse`·`parseBatch` 호출 방식을 테스트로 옮겨 실행했다.
다른 문서 파일로 다시 저장하는 변환기가 아니라 각 입력을 `DocumentParseResult`로 읽는 검증이다.

## 실행한 내용

- 기존 외부 원본 60개·20형식을 각각 URL과 Data로 읽음: **120회 통과**.
- 형식별 1개씩 20개에 CGImage와 손상 PDF를 섞은 22개 배치: **정상 21개·개별 실패 1개**.
  입력 순서·진행 이벤트·결과와 블록 텍스트의 일관성 확인. 배치 API 0.935초.
- CGImage 직접 입력: 한영 문구 `LABCORD 사용법 123` 확인, 위치·신뢰도 반환.
- 같은 문구를 직접 JPEG·PNG·HEIC·TIFF로 인코딩한 4개: 각 15자·경고 0개, 문구 확인.
- Task 취소 예제: 취소 오류 반환 확인. 즉시 취소 검증이며 긴 동기 OCR의 중단 지연을 측정하지 않음.

API 예제 5개를 포함해 **일반 회귀 115개 통과·실패 0개**, XCTest 23.783초.
위 입력 시도는 총 148개이며 정상 결과 146개, 의도한 손상 1개·취소 1개다.
큰 문서 반복 성능 검사는 이번 회귀에서 제외했다. 위 0.935초는 작은 샘플 배치의 단일 관찰이며
대용량 처리 속도나 기기 간 성능을 보장하는 수치가 아니다.

## 형식별 실제 결과

각 형식의 외부 원본 3개 × URL·Data 2가지 입력이다. 글자 수는 6회 결과의 범위,
표 셀·그림 수는 그중 최댓값이다. 일반 문서 전체나 해당 형식의 모든 요소를 검증한 것은 아니다.

| 형식 | 읽기 완료 | 글자 수 범위 | 표 셀 최대 | 내장 PNG 최대 |
| --- | ---: | ---: | ---: | ---: |
| CSV | 6/6 | 1120–60918 | 2682 | 0 |
| DOC | 6/6 | 135–994 | 6 | 2 |
| DOCX | 6/6 | 18–135 | 3 | 2 |
| HEIC | 6/6 | 0–0 | 0 | 0 |
| HTML | 6/6 | 21–199 | 0 | 0 |
| HWP | 6/6 | 42–1711 | 36 | 4 |
| HWPX | 6/6 | 101–2229 | 36 | 4 |
| JPEG | 6/6 | 257–876 | 0 | 0 |
| JSON | 6/6 | 1297–16624 | 0 | 0 |
| MARKDOWN | 6/6 | 4353–9772 | 0 | 0 |
| PDF | 6/6 | 20–1039 | 0 | 1 |
| PNG | 6/6 | 11–3360 | 0 | 0 |
| PPT | 6/6 | 0–219 | 0 | 2 |
| PPTX | 6/6 | 83–237 | 32 | 0 |
| RTF | 6/6 | 10–1028 | 0 | 0 |
| TIFF | 6/6 | 0–59 | 0 | 0 |
| TXT | 6/6 | 1562–166468 | 0 | 0 |
| XLS | 6/6 | 143–7311 | 538 | 0 |
| XLSX | 6/6 | 759–16109 | 2566 | 0 |
| XML | 6/6 | 26–8881 | 0 | 0 |

그림 파일 자체의 OCR 결과는 `imageOCR` 블록이다. 입력 이미지 전체를 `result.images`에
다시 넣는 API는 아니므로 JPEG·PNG·HEIC·TIFF의 내장 PNG 수 0은 OCR 실패를 뜻하지 않는다.

## 주의해서 볼 결과

- 원본 HEIC 3개는 사진이며 텍스트가 0자다. 이 결과만으로 문자 인식이 검증됐다고 세지 않았다.
  별도로 만든 한영 HEIC에서 실제 문구와 15자를 확인했다.
- DOCX `VariousPictures`는 본문·지원되는 그림 2개를 반환했지만 URL·Data 각각
  `imageOCRFailed` 경고 3개가 남았다. 모든 삽입 그림을 읽었다고 처리하지 않는다.
- HTML `about.html`은 URL·Data의 본문·블록·이미지 지문이 같다. 로컬 참조 그림을 읽으려는
  URL 입력에서는 읽기 실패 경고, 기준 디렉터리가 없는 Data 입력에서는 건너뜀 경고가 나왔다.
  참조 그림 원본이 샘플 옆에 없는 경우이며 외부 다운로드로 보충하지 않았다.
- 60개 전부의 URL·Data 블록·PNG 지문이 같았다. 경고까지 포함하면 위 HTML을 제외한 59개가 같았다.
- 구형 DOC·PPT, HWP·HWPX, 일부 HTML·Markdown에는 읽기 순서 불확실 경고가 있다.
  HWPX의 미지원 요소 경고도 보존했다. 경고 없는 완전 복원으로 표현하지 않는다.
- 표·문구 확인은 기존 부분 정답을 사용한다. 모든 페이지 문자 오류율이나 모든 표의 정답률을 측정한 것은 아니다.

## 코드와 재현

[실행한 Swift 테스트](../../../../../ResearchersTests/DocumentParsing/RealWorld/DocumentAPIUsageTests.swift),
[입력별 수치·지문](API-Usage-Metrics.json), [원본 명세](../Corpus/Real-World-Corpus.md).
본문·이미지 바이트를 로그나 수치 JSON에 넣지 않고 개수·경고 코드·해시만 보관했다.

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -configuration Release -destination 'platform=iOS,id=연결된_기기_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ResearchersTests/DocumentAPIUsageTests \
  -resultBundlePath /tmp/ResearchersAPIUsage-고유이름.xcresult \
  DEVELOPMENT_TEAM=사용가능한_팀 CODE_SIGN_STYLE=Automatic ENABLE_TESTABILITY=YES
swiftlint lint --strict
```

전체 일반 회귀는 [기존 회귀 명령](../Performance/Batch/Memory-Peak-Optimization.md)의 제외 목록으로 실행했다.
새 스크립트·의존성을 추가하지 않았으며 앱 파서 45개 소스 해시는 기존 측정 버전과 같다.
strict lint는 101개 파일·위반 0개다.

첫 시도에서는 배치 샘플 ID가 `-01`로 끝난다고 가정해 HWP·HWPX가 빠져 테스트 1개가 실패했다.
테스트의 선택 기준을 형식별 그룹으로 고친 후 다시 실행했다. 앱 파서의 실패로 기록하지 않으며
최초 실패 번들은 `/tmp/issue21-api-usage-device.xcresult`에 보존한다.
최종 증거는 `/tmp/issue21-api-usage-raster-final.xcresult`다. xcresult·서명 자산은 커밋하지 않는다.
