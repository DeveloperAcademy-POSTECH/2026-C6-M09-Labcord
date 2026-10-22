# 문서 파싱 후속 품질 검증

이 문서는 잔여 기능 보완 전의 분석 기록이다. 병합 셀·그림 설명·금액 OCR의 최신 상태는
[잔여 보완 검증](Remainder-Verification.md)을 따른다.

2026-10-21. 기존 변경을 보존하고 테스트·정답·분석 도구·검증 문서를 보완했다.
앱 파싱 API·의존성·폴더 구조·최소 iOS 27.0·Swift 언어 모드 5.0은 변경하지 않았다.
새 외부 파일을 다운로드하거나 앱에 테스트 자산을 포함하지 않았다.

## 1. 누리 HWP·HWPX 원본 대조

[원본 대조 집계](../Corpus/Noori-Source-Comparison.json),
[백엔드 진단 집계](../Corpus/Noori-Backend-Diagnostics.json).

| 항목 | 원본 HWPX | HWP 결과 | HWPX 결과 |
| --- | --- | --- | --- |
| XML hp:t 텍스트 구간 | 115 | 공백 제외 검색으로 전부 확인 | 공백 제외 검색으로 전부 확인 |
| 표 | 5 | 5 | 5 |
| 셀 | 빈/그림 전용 포함 40 | 텍스트 셀 36 | 텍스트 셀 36 |
| 내장 그림 | 4 | 4 | 4 |
| 일반 문단 | 원본 직접 비교 | 11 | 11 |
| 이미지 OCR 블록 | 인식 정답은 별도 필요 | 10 | 10 |

앱에서 추출한 비 OCR 블록의 텍스트·위치·순서는 두 파일에서 동일했다.
OCR 문구와 중복 개수도 같지만 그림의 BinData 순서가 달라 전체 OCR 반환 순서는 다르다.
두 결과 모두 이미지 앵커·읽기 순서를 확정하지 못한다는 경고를 보존한다.
빈/그림 전용 셀 4개가 텍스트 셀로 반환되지 않은 것을 본문 누락 4건으로 세지 않는다.

HWPX `unsupportedElement` 198건은 모두 CoreHwp의 `unknownRecord` 진단이다.
복구 placeholder로 대체된 문단·구역·메모는 없었다.
DocInfo 143건, section 55건이며 합성 레코드의 XML 요소명을 따로 집계했다.
주요 항목은 `autoSpacing` 47, `tabItem` 39, `slash`·`backSlash` 각 20,
`typeInfo` 13이다. 도형 크기·변환·효과·배치와 페이지 테두리 관련 요소도 있다.
198건을 본문 누락 198건으로 해석하거나 일괄 숨기지 않는다.

### 실제 남은 손실·불확실성

- XML 텍스트 구간 검사는 `hp:t`만 대상으로 한다. 반복 횟수·문자별 원본 위치·조판 전체의
  일치를 보장하지 않는다. HWP는 동일 문서의 HWPX를 대조 기준으로 사용했으며,
  별도의 한컴 렌더러로 바이너리 전체 페이지를 재검증하지 않았다.
- `shapeComment` 3개에 있는 그림 파일명·크기·촬영일 설명은 결과에 반환되지 않는다.
  본문 hp:t 누락은 없지만 그림 설명 메타데이터 손실은 남아 있다.
- 원본 표에 열 3개를 병합한 셀 1개가 있다. 현재 HWP 어댑터는 텍스트와 행·열 좌표를
  반환하지만 이 셀의 columnSpan은 보존하지 않는다. 이는 정답 검사 통과와 별개인 제약이다.
- 그림 OCR을 원래 표 셀·페이지에 연결하는 앵커와 읽기 순서는 미확정이다.
  원본 자체 텍스트와 OCR의 의미상 중복 여부도 전수 정답을 갖춘 상태는 아니다.

원본 XML/저장된 공개 파싱 스냅샷 비교는 아래 스크립트로 재현한다.
스냅샷은 앞선 60개 미리보기 내보내기 실행의 실제 앱 결과이며 가짜 결과가 아니다.
이번 XCTest는 별도로 두 원본을 다시 파싱하고 native 블록·OCR 문구 집합을 비교했다.

```sh
python3 "docs/Technical Verification/LabcordParser/Tools/compare_noori_sources.py" \
  공개_샘플_파싱_JSON_폴더 --output /tmp/noori-comparison.json
```

## 2. 샘플별 부분 정답과 회귀 검사

`ResearchersTests/Fixtures/RealWorld/GoldenAssertions.json`에 60개 샘플별 ID·원본 해시·
근거·텍스트 앵커를 기록했다. 기존 대조 문구를 이어받고 독립 원본 근거를 추가했다.
실제 파서 출력으로 정답을 생성하지 않는다.

- HWPX 3개 XML과 동일 누리 HWP 대조에 대해 총 251개 원본 텍스트 구간 검사.
- HWP/HWPX·Word 표·PPTX 표에 대해 총 110개 텍스트 셀의 값·행·열 검사.
  공백만 제거하며 기호·숫자·글자는 보정하지 않는다. 같은 셀을 두 번 정답에 쓰면
  실제 결과에서도 일치 블록을 각각 소비하므로 하나의 블록으로 중복 충족시키지 않는다.
- DOC 2×3 표와 PPTX 표의 원본 순서, PDF 두 열의 행 우선 읽기 순서 검사.
- 누리 HWP/HWPX와 그림 전용 PPT에 정확한 그림 개수 검사.
- 정답 ID가 정확히 60개 원본과 일치하는지 검사하고, 누락·좌표 오류·순서 뒤바뀜·
  그림 개수 오류를 가진 가짜 결과가 검사를 통과하지 못하는 음성 테스트 추가.

이는 부분 정답이다. 60개 전부에 전체 본문·모든 표 셀·모든 그림·읽기 순서 정답을
완성했다는 뜻은 아니다. 자연 사진은 문자 정답이 없으며 원래의 디코딩 검사를 유지한다.
표 ID가 없는 결과에서 같은 좌표·값이 여러 표에 반복되면 표 사이 소속까지 판별할 수 없다.

```sh
python3 "docs/Technical Verification/LabcordParser/Tools/generate_golden_assertions.py"
python3 "docs/Technical Verification/LabcordParser/Tools/verify_real_world_corpus.py"
```

재생성 결과: 60개, 셀 110개, 원본 텍스트 구간 251개.
원본 검증: 60개·20형식·6,029,910바이트, 해시 일치.

## 3. 숫자·금액 OCR 측정

[현재 측정 JSON](../OCR/Numeric-OCR-Metrics.json).
`DocumentNumericOCRTests`는 원본 대출 계산기 화면의 금액 영역 3개를 육안 대조해
정답으로 고정하고 위치 기반으로 실제 Vision 결과를 대응한다.
공백·통화·숫자를 자동 교정하지 않으며 Levenshtein 문자 오류율을 기록한다.
추가로 편집 거리 계산 자체와 자체 생성 숫자 이미지 `12345.67`의 정확한 인식을 검사한다.

| 정답 | 실제 인식 | 편집 거리 |
| --- | --- | --- |
| $94.36 | $94.36 | 0 |
| $661.37 | S661.37 | 1 |
| $5,661.37 | 55,661.37 | 1 |

금액 완전 일치율 **1/3 = 33.3%**, 합산 문자 오류율 **2/22 = 9.09%**.
한 스크린샷의 세 금액으로 일반적인 OCR 정확도를 추정할 수 없다.
숫자로 보이는 문자에 임의 보정을 적용하면 정상 숫자까지 바꿀 수 있어 적용하지 않았다.

이 측정 테스트의 통과는 ROI 결과·측정 첨부가 완성됐다는 뜻이다.
통화 정확도 제품 합격선을 통과했다는 뜻은 아니다. 오류 2개는 해결되지 않은 품질 문제다.
점수는 공개 샘플용 XCTest 첨부에만 저장하며 앱 운영 로그에는 추가하지 않는다.

## 4. 실기기 검증 계획

[기기별 성능·취소 검증 계획](../Performance/Baseline/Device-Performance-Plan.md)에 실행 전제·명령·행렬·
측정 도구·성공/실패 조건·결과표를 작성했다.
연결된 iPhone 17은 확인했지만 이 작업에서 앱 설치·실기기 실행은 하지 않았다.
요청한 네 번째 작업은 계획 작성이며, 실기기 메모리·시간·취소 지연은 미측정이다.

## 최종 실행 결과

- Xcode 27.1, iPhone 17 시뮬레이터 iOS 27.0.
- XCTest **72개 통과, 실패 0건**, 실행 **39.147초**.
- 신규 테스트 7개: 정답 검증 2개, 누리 대조/진단 2개, 숫자 OCR 3개.
- 기존 65개도 통과했고 그중 코퍼스 20개 형식 테스트가 새 정답을 함께 검사했다.
- 앱 빌드 성공, strict lint **68개 파일·위반 0건**, `git diff --check` 통과.
- 실기기 성능·모든 요소의 정답·금액 OCR 품질 문제는 위 제약으로 별도 표시했다.

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/issue21-quality-final.xcresult
xcodebuild build -project Researchers.xcodeproj -scheme Researchers \
  -destination 'generic/platform=iOS Simulator'
swiftlint lint --strict
```

xcresult `/tmp/issue21-quality-final.xcresult`, 테스트 로그
`/tmp/issue21-quality-final-test.log`, 빌드 로그
`/tmp/issue21-quality-final-build.log`, 린트 로그
`/tmp/issue21-quality-final-lint.log`.
최종 전체 XCTest에서 앱/테스트 빌드도 성공했고 CI 앱 빌드 명령을 별도로 실행했다.
새 의존성·새 라이선스는 없고 기존 외부 샘플의 출처·고지는 계속 적용한다.
