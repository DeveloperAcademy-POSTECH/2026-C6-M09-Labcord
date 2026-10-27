# Entry 한글 폰트와 텍스트 배치

홈과 등록 화면에서 사용하는 한글 폰트의 출처, 파생 과정과 Figma 비교 근거를 기록합니다.
사용자 흐름과 저장 계약은 [Entry 구현 안내](experiment-entry.md)에 있습니다.
현재 두 화면의 실제 픽셀 비교는 진행 중입니다. 아래 기하 검증과 폰트 재현 성공만으로
전체 화면의 1:1 일치를 확정하지 않습니다.

## 원본과 앱 자원

원본은 공식 [google/fonts](https://github.com/google/fonts)의 Noto Sans KR variable입니다.
다음 커밋과 SHA256을 고정하며 최신 원본으로 자동 교체하지 않습니다.

| 항목 | 값 |
| --- | --- |
| 커밋 | [4efc2774c63917927efe769ca845def6bd6debae](https://github.com/google/fonts/commit/4efc2774c63917927efe769ca845def6bd6debae) |
| 원본 | [NotoSansKR\[wght\].ttf](https://raw.githubusercontent.com/google/fonts/4efc2774c63917927efe769ca845def6bd6debae/ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf) |
| 버전 | `Version 2.004-H2;hotconv 1.0.118;makeotfexe 2.5.65603` |
| 원본 SHA256 | `194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252` |
| 라이선스 | [고정 커밋의 SIL Open Font License 1.1 원문](https://raw.githubusercontent.com/google/fonts/4efc2774c63917927efe769ca845def6bd6debae/ofl/notosanskr/OFL.txt) |
| OFL SHA256 | `1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9` |

앱에는 원본 전체 대신 weight 400/500을 정적으로 인스턴스화한 한글 서브셋 두 개와
[OFL 원문](../Researchers/Resources/Fonts/NotoSansKR-OFL.txt)을 포함합니다.

| 자원 | weight | 크기 | SHA256 |
| --- | ---: | ---: | --- |
| [LabcordEntryHangul-Regular.ttf](../Researchers/Resources/Fonts/LabcordEntryHangul-Regular.ttf) | 400 | 2,837,844 bytes | `75468a2a640001c36adbfef4074ce985953d7376812efbf969631239cd4c84a2` |
| [LabcordEntryHangul-Medium.ttf](../Researchers/Resources/Fonts/LabcordEntryHangul-Medium.ttf) | 500 | 2,837,576 bytes | `b4c2063be71949f1040b08a359376471876fe8f9fc0ca399e5e147b20c0b9346` |

두 TTF의 합계는 **5,675,420 bytes, 약 5.7MB**입니다. OFL 4,388 bytes는 별도입니다.
원본의 저작권·버전·라이선스 name 레코드를 보존합니다. 원본 저작권은 Adobe이며
Reserved Font Name은 `Source`입니다. 파생 파일은 원본 이름과의 충돌과 RFN 사용을 피하도록
family를 `Labcord Entry Hangul`, PostScript 이름을 `LabcordEntryHangul-Regular`와
`LabcordEntryHangul-Medium`으로 바꿉니다. 배포 시에도 OFL 원문을 자원과 함께 유지합니다.

## 서브셋과 검증 범위

포함할 Unicode 범위는 U+0020, U+AC00–D7A3, U+1100–11FF, U+3130–318F,
U+A960–A97F, U+D7B0–D7FF, U+FFA0–FFDC입니다. 원본이 제공하는 11,676개 Unicode와
`.notdef`, 한글 조합·대체 및 composite 참조에 필요한 비인코딩 glyph를 보존합니다.
총 glyph는 13,482개입니다. 요청 범위 중 원본에 없는 예약 코드포인트 22개는 생성된
`manifest.json`의 `sourceMissingRequestedCodepoints`에 기록합니다.

폰트에는 공백 외 Latin·숫자·문장부호 cmap을 포함하지 않습니다. `EntryAppearance.labelText`는
한글에만 이 폰트를 지정하고 Latin·숫자·공백은 system font run으로 유지합니다.
`headline`의 한글은 Medium 500, 나머지 역할은 Regular 400입니다. 이것은 비교한 Figma의
SF Pro Semibold 590에 대한 한글 매핑이며 모든 590/600 weight에 적용하는 일반 규칙은 아닙니다.
문자 간격은 한글에만 역할의 tracking을 적용합니다. 시스템 font run의 공백에는 tracking을
중복 적용하지 않으며 혼합 문자열의 전체 폭을 별도 비교합니다.

재현 시 고정 weight의 전체 정적 인스턴스와 서브셋의 모든 retained glyph를 비교합니다.
좌표·contour·composite 참조·advance/side bearing·glyph instructions가 같아야 통과합니다.
원본에서 제공하는 `prep`, `gasp` 힌팅 테이블도 동일하게 유지합니다.
별도 시뮬레이터 CoreText CLI에서는 Regular `실험제목` 4개와 Medium `진행중인실험` 6개의
전체 CGPath 명령·좌표·bounds가 서브셋 전후 완전히 같은 것을 확인했습니다.

## Figma 윤곽 근거

원본은 [최신 디자인 페이지](https://www.figma.com/design/v6cxQ2I6zURWYQaG5pnuBL?node-id=502-7591)의
홈 `502:12299`와 등록 `502:12563`입니다. 원본 캔버스를 수정하지 않고 SVG outline을 읽었습니다.

| 비교 대상 | Figma 선언 | 확인한 한글 윤곽 |
| --- | --- | --- |
| 홈 본문 `502:12303`, `실험 제목` | SF Pro Regular 400, 17/22, tracking −0.43 | Noto Regular 400, 4 glyph |
| 홈 헤더 `502:12343`, `진행 중인 실험` | SF Pro Semibold 590, 17/22, tracking −0.43 | Noto Medium 500, 6 glyph |

두 역할 모두 Noto 정적 인스턴스와 contour 수·순서·선분 종류·glyph bounds가 맞습니다.
CoreText의 TrueType 암시적 중간점은 half font unit을 보존하므로 native 경로와 SVG 사이에
최대 약 0.012pt의 제어점 차이가 있습니다. **비교 계산에서만** 이 중간점을 font unit 정수로
내림하고 quadratic을 cubic으로 바꾸면 본문 최대 0.000067pt, 헤더 최대 0.000083pt 차이로
일치합니다. 이는 SVG 직렬화 자릿수 수준입니다. 후보 폰트 파일에는 이 내림이나 추가 스케일·
glyph 좌표 변형을 적용하지 않습니다.

Figma API의 선언 font name은 내부 한글 fallback 파일 이름을 공개하지 않습니다.
위 결과는 측정한 한글 윤곽의 동등성을 뒷받침하며 Figma 내부 파일 이름 자체를 확정하지 않습니다.
기본 iOS Apple SD와 Pretendard는 이 윤곽과 다르므로 글꼴 크기 확대만으로 차이를 없앨 수 없습니다.
동일 윤곽이어도 baseline·tracking·공백의 font run·래스터라이저 AA가 달라질 수 있어
최종 판정은 같은 기기의 두 시뮬레이터 화면을 원본과 대조한 결과로 합니다.

## 원본 AA의 고정 샘플 가설

외부 시뮬레이터 CLI에서 원본 SVG 첫 `실`의 각 픽셀을8×8 중앙 후보점으로 검사했습니다.
64개 후보 중 같은16개를 선택하는 이진 제약의 유일해가 있었고, ROI2,622px의 coverage-count를
모두 설명했습니다. 선택 bit mask는 `4411882244118822`이며 bit index는 `row * 8 + column`입니다.
이 count 변환은 가설 검증용입니다. 최종 RGB 비교에서는 원본 PNG를 변형하지 않았습니다.

같은 패턴을 다시 맞추지 않고 원래 좌표의 다른 글자에도 적용했습니다.

| 대상 | 원본 RGB L1 | 최대 채널 차이 | 남은 예외 |
| --- | ---: | ---: | --- |
| 학습 `실` | 288 | 1 | 96px의1단계 차이 |
| 미학습 `험`·`제`·`목`·공백 | 501 | 16 | `제`의1px는16단계 차이 |
| 헤더 전체 | 1,434 | 17 | 1px는17단계 차이 |

첫 글리프에서 성립한 패턴을 범용 렌더링 규칙이나 Figma의 실제 PNG export backend로
확정하지 않습니다. 앱은 Native Text와 `EntryTextRenderer`를 유지하며, 이 실험으로 폰트
윤곽·원본 이미지·앱 렌더러를 바꾸지 않았습니다. 입력 SHA·좌표·제약·시간·생성 PNG·예외는
외부 QA의 `font-raster-analysis/msaa16-once/`에 보존합니다. 전체 화면의 일치 기준은
[원본 PNG 비교](entry-verification.md#원본과-전체-화면-비교)를 유지합니다.

## 베이스라인과 행높이

Regular와 Medium의 ascender/descent/leading 메트릭은 같습니다. descent는 양수 크기이며
UIKit의 `descender`는 그 음수입니다. 값은 픽셀 대신 pt입니다.

| 크기 | ascent | descent | leading | 기본 UIKit lineHeight |
| ---: | ---: | ---: | ---: | ---: |
| 12 | 13.920 | 3.456 | 0 | 17.376 |
| 13 | 15.080 | 3.744 | 0 | 18.824 |
| 15 | 17.400 | 4.320 | 0 | 21.720 |
| 17 | 19.720 | 4.896 | 0 | 24.616 |
| 20 | 23.200 | 5.760 | 0 | 28.960 |

목표 baseline은 원본의 `absoluteRenderBounds.y - node.y + glyph ymax`로 구했습니다.
13pt 사진·파일 문구는 한글을 Noto, Latin을 iOS system Regular로 섞은 CTLine을 측정했으며
최고점은 한글이 결정합니다. 혼합 ink 높이 13.080590pt도 원본 13.080566pt와 맞습니다.
Noto를 행 안에 중앙 배치할 때의 baseline은 `(행높이 + ascent - descent) / 2`입니다.

| 역할·원본 | 크기/행높이 | 원본 목표 baseline | Noto 중앙 baseline | 기하 계산 기준 보정 |
| --- | ---: | ---: | ---: | ---: |
| headline/body, `502:12343`/`502:12303` | 17/22 | 17 | 18.412 | −1.412 |
| subheadline, 진행 중 `502:12350` | 15/20 | 15 | 16.540 | −1.540 |
| footnote, 사진 `502:12570`·파일 `502:12600` | 13/18 | 14 | 14.668 | −0.668 |
| caption, 프로토콜 없이 진행 `1361:16643` | 12/16 | 12 | 13.232 | −1.232 |
| title, 실험 등록 `502:12583` | 20/25 | 20 | 21.220 | −1.220 |

원본 절대좌표의 직렬화 차이는 최대 약 0.000215pt여서 목표값을 정수로 표시했습니다.
13/18만 목표 baseline이 글꼴 크기보다 1pt 큽니다. 이 관계를 다른 크기·행높이에 일반화하지
않습니다. 표는 기하 계산 기준이며 실제 SwiftUI 배치와 AA에 대한 최종 화면 보정은 별도입니다.
현재 3x 캡처를 기준으로 subheadline·footnote는 아래 1px를 추가 보정합니다.
headline·body·caption은 계산값을 유지하며, 등록 제목은 내비게이션 표시 위치에서 보정합니다.
이 값도 화면 비교 대상이며 전체 픽셀 일치 완료를 의미하지 않습니다.

## 표시 계층과 디자인시스템 교체

- [EntryAppearance](../Researchers/Features/ExperimentEntry/Presentation/EntryAppearance.swift)는
  `Bundle.main`의 두 TTF를 프로세스 범위로 한 번 등록하고 한글 font run과 tracking을 만듭니다.
  등록 성공과 한글 여부를 기준으로 Noto baseline 보정 여부도 결정합니다.
- [EntryText](../Researchers/Features/ExperimentEntry/Presentation/EntryText.swift)의 역할은
  크기·행높이·tracking·측정 baseline을 한 곳에 묶습니다. 시스템 폰트로 fallback하면 Noto용
  baseline 보정을 적용하지 않습니다.
- 네이티브 `TextRenderer`에서 공개 옵션
  [disablesSubpixelQuantization](https://developer.apple.com/documentation/swiftui/text/layout/drawingoptions/disablessubpixelquantization)을
  사용해 글리프의 소수 픽셀 위치를 유지합니다. 기본 Text의 레이아웃·줄임표·접근성은 유지합니다.
- 날짜의 기본 system 15pt·광학 크기를 유지하고 추가 tracking `0.004375pt`를 적용합니다.
  비교한 `2026.10.13`의 CoreText 원점과 Figma SVG 원점 차이는 최대 `0.0000461pt`,
  잉크 폭 차이는 `0.000000305pt`였습니다. 이 값은 해당 15pt 스타일의 비교 결과입니다.
- 실제 앱은 `Researchers/Resources/Fonts`를 앱 자원으로 포함합니다. 별도 QA 생성기는 같은
  폴더를 `EntryQA` 앱의 동기화 resource group에 연결합니다. 테스트 bundle이나 기존
  LabcordDesignSystem의 `Bundle.module`에 넣은 폰트를 `Bundle.main`으로 찾는 구조가 아닙니다.

현재 기존 LabcordDesignSystem API는 사용하지 않습니다. 이후 DS 컴포넌트로 교체할 때
`EntryAppearance`·`EntryText`와 주변 표시 컴포넌트를 바꾸고, Feature·저장소·UUID delegate 계약은
유지합니다. 폰트 자원을 패키지로 옮길 경우 해당 패키지의 resource bundle 조회와 QA 연결도
함께 바꿔야 합니다. 고정 크기는 현재 원본 비교를 위한 값이며 Dynamic Type 지원을 검증한 것은 아닙니다.

## 외부 폴더에서 재현

[prepare-entry-fonts.py](../scripts/verification/prepare-entry-fonts.py)는 필수 인자로 받은
저장소 외부 폴더에만 원본·작업·결과를 만듭니다. 저장소 내부 출력과 출력 폴더 밖으로 연결된
하위 symlink를 거절하고, 앱 자원을 자동 복사하거나 덮어쓰지 않습니다. 기존 원본의 해시가
다르면 덮어쓰지 않고 실패합니다. 고정된 생성 결과 파일은 외부 출력 폴더에서 다시 생성됩니다.

Python 3.9 이상과 외부 분석용 `fontTools==4.60.2`를 사용합니다.
fontTools를 앱·Swift Package 의존성으로 추가하지 않습니다. 저장소 루트에서 실행합니다.

```sh
python3 -m venv /tmp/labcord-entry-font-env
/tmp/labcord-entry-font-env/bin/pip install 'fonttools==4.60.2'
/tmp/labcord-entry-font-env/bin/python scripts/verification/prepare-entry-fonts.py \
  /tmp/labcord-entry-font-output
```

출력 구조는 다음과 같습니다.

```text
source/NotoSansKR-variable.ttf             고정 원본
OFL.txt                                   고정 원본 라이선스
work/LabcordEntryHangul-*-full.ttf          서브셋 이전의 정적 인스턴스
fonts/LabcordEntryHangul-*.ttf              검증을 통과한 비교 자원
manifest.json                             출처·해시·크기·문자 범위·glyph 검증 결과
```

원본·OFL SHA256, fontTools 버전, 전체 retained glyph 비교, 저작권·버전·라이선스 보존,
힌팅 보존과 최종 TTF 기준 SHA256이 모두 맞아야 성공합니다. 생성만으로 앱 자원을 교체하지
않습니다. 채택 시 위 자원 두 개와 OFL을 비교·반영하고 별도 QA 호스트에서 두 화면을 검증합니다.
시뮬레이터 명령은 [Entry 검증 안내](experiment-entry.md#시뮬레이터-검증)를 따릅니다.

OFL은 고정 해시의 원문 그대로이며 21행 끝 공백도 보존합니다. 따라서 전체 변경의
`git diff --check`는 이 원본 한 줄을 보고할 수 있습니다. 앱 코드의 공백 검사와 라이선스
원문 해시 검증을 구분하며, 검사 통과를 위해 라이선스 내용을 수정하지 않습니다.
