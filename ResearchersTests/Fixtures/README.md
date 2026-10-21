# 파싱 검증 자산

이 디렉터리 루트의 샘플은 자체 생성했다. 본문과 표는 검증용 문자열,
그림은 시스템 글꼴로 직접 만든 `IMAGE OCR MARKER 123` PNG이다. 글꼴 파일은 포함하지 않는다.

`RealWorld/`에는 별도로 수집한 외부 원본 60개가 있다. 형식별 목록·기대 결과·검증 방법은
[외부 코퍼스 안내](../../docs/LabcordParser/Real-World-Corpus.md), 출처와 라이선스 고지는
[외부 자산 고지](../../docs/LabcordParser/ThirdPartyFixtures/README.md)에 기록한다.

| 파일 | 생성 방법 | 검증 대상 |
| --- | --- | --- |
| LegacySample.doc | 자체 ODT를 로컬 LibreOffice의 MS Word 97 필터로 변환 | CFB/Word piece table, 셀·행 구분, OfficeArt 그림 |
| LegacySample.xls | 자체 ODS를 MS Excel 97 필터로 변환 | BIFF 셀, DrawingGroup·CONTINUE 그림 |
| LegacySample.ppt | 자체 ODP를 MS PowerPoint 97 필터로 변환 | 사용 중인 슬라이드, 그룹 표, 내장 PNG |
| BinarySample.hwp | HWP 5.0.2.2 레코드와 CFB를 직접 작성 | 비압축 본문·표·BinData |
| BinaryCompressed.hwp | 동일 레코드와 BinData를 raw DEFLATE로 압축 | 압축 스트림과 이미지 해제 |
| LegacyImage.png | Pillow와 macOS 시스템 Arial로 생성 | 문서 내 이미지 OCR |

Office 세 파일은 확장자만 바꾼 XML이 아니라 CFB 시그니처가 있는 바이너리이다.
HWP 두 파일은 `HwpFile`의 복구 옵션 없는 읽기와 앱 API 양쪽에서 검증한다.
Hancom 편집기로 생성한 모든 버전·컨트롤의 호환성을 증명하는 코퍼스는 아니다.

## 다시 생성하기

저장소 루트에서 다음을 실행한다. 생성 도구는 앱의 런타임 의존성에 포함되지 않는다.
테스트 실행과 앱 빌드는 이미 생성된 자산을 사용하므로 LibreOffice나 Pillow가 필요 없다.

```sh
python3 scripts/DocumentParsing/generate_legacy_fixtures.py
python3 scripts/DocumentParsing/generate_hwp_fixture.py
```

생성 환경은 LibreOfficeDev 26.8.0.0.alpha0, Python 3, Pillow이다.
Office 바이너리에는 생성 시간 등 도구 메타데이터가 있어 재생성 시 바이트 해시는 달라질 수 있다.
자산을 재생성하면 아래 앱 테스트도 다시 실행해야 한다.

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' \
  -parallel-testing-enabled NO
```
