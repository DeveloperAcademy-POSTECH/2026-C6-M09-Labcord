# Entry 시스템 기본 폰트

2026-10-28 사용자 요청에 따라 홈과 실험 등록 화면은 SwiftUI `Text`와
`.system(size:weight:)`를 사용합니다. 한글·영문·숫자의 실제 글꼴과 fallback은 OS가 결정합니다.
별도 Noto 폰트 등록, 문자별 폰트 지정, 커스텀 TextRenderer, 자간·베이스라인 보정은 없습니다.
앱에 포함했던 한글 TTF 두 개와 OFL은 제거했습니다.

## 표시 역할

| 역할 | 크기 | 굵기 | 행높이 |
| --- | ---: | --- | ---: |
| headline | 17pt | semibold | 22pt |
| body | 17pt | regular | 22pt |
| subheadline | 15pt | regular | 20pt |
| footnote | 13pt | regular | 18pt |
| caption | 12pt | regular | 16pt |
| title | 20pt | regular | 25pt |
| 날짜 | 15pt | regular | 20pt |

글자 크기·굵기·행높이는 기존 화면 역할을 유지합니다. Dynamic Type 지원은 아직 검증하지 않았습니다.
폰트 변경으로 Figma와 글자 윤곽·문자열 폭이 달라질 수 있으며, 이전 Noto 적용 빌드의
픽셀 비교 결과를 현재 기본 폰트 화면의 결과로 사용하지 않습니다.

[EntryText](../Researchers/Features/ExperimentEntry/Presentation/EntryText.swift)와
[EntryAppearance](../Researchers/Features/ExperimentEntry/Presentation/EntryAppearance.swift)에
표시 역할을 모아 추후 디자인시스템 폰트 API로 교체할 수 있습니다.
Feature·저장소·UUID 계약은 폰트와 독립적입니다.

## 이전 비교 도구

[prepare-entry-fonts.py](../scripts/verification/prepare-entry-fonts.py)는 이전 Figma 윤곽 조사와
폰트 재현을 위한 외부 QA 도구로 보존합니다. 앱 빌드에서 실행하지 않으며 생성 폰트를 앱에
복사하거나 등록하지 않습니다. 현재 시스템 폰트 적용에 이 도구나 fontTools 설치는 필요하지 않습니다.
