# Entry 아이콘 벡터 출처와 배치

홈의 설정·추가, 등록 화면의 뒤로 가기 아이콘은 선택된 Figma 텍스트 leaf의 SVG 윤곽입니다.
원본 SVG 바이트와 앱 자원의 동일성을 확인했습니다. 시뮬레이터의 버튼 프레임은 원본과 같고,
벡터 적용 후 전체 화면 오차가 줄었습니다. 최종 RGBA·AA에는 차이가 남아 있습니다.
한글 폰트의 출처·베이스라인은 별도 [폰트 문서](entry-fonts.md)에 있습니다.

## 원본과 내보내기

원본은 Figma 파일 `v6cxQ2I6zURWYQaG5pnuBL`, 페이지 `502:7591`의
[홈 `502:12299`](https://www.figma.com/design/v6cxQ2I6zURWYQaG5pnuBL?node-id=502-12299)와
[등록 `502:12563`](https://www.figma.com/design/v6cxQ2I6zURWYQaG5pnuBL?node-id=502-12563)입니다.

| 아이콘 | 버튼 parent | 실제 Text leaf |
| --- | --- | --- |
| gear | `502:12342` | `I502:12342;5522:11872;5522:11881` |
| plus | `502:12341` | `I502:12341;5522:11869;5522:11894` |
| back | `502:12585` | `I502:12585;6491:22970;5431:837` |

세 leaf 모두 SF Pro Medium, `wght=510`, `wdth=100`, 17pt, tracking0입니다.
원본 수정 없이 각 버튼의 TEXT 자식을 찾고 `exportAsync`의 `SVG_STRING`,
`svgOutlineText=true`, `contentsOnly=true`, `useAbsoluteBounds=false`로 내보냈습니다.
각 SVG는 path 하나이며 `<text>`·폰트 파일·래스터 `<image>`를 포함하지 않습니다.
원본의 배경·그림자·전체 버튼 PNG·전체 화면 캡처는 앱 자원으로 사용하지 않습니다.

## 원본 바이트 보존

`Researchers/Resources/Assets.xcassets`의 imageset에 원본 SVG를 그대로 복사했습니다.
path·색상·viewBox를 재작성하거나 곡선·좌표를 단순화하지 않았습니다.
각 `Contents.json`은 `preserves-vector-representation=true`를 사용합니다.

| 자원 | bytes | 원본과 앱 자원의 동일 SHA256 |
| --- | ---: | --- |
| [EntryGear/gear.svg](../Researchers/Resources/Assets.xcassets/EntryGear.imageset/gear.svg) | 11,646 | `d0a28750623adec300d1e5901840b1fb12f4c97ff13db78ab9df370bbf3b5564` |
| [EntryPlus/plus.svg](../Researchers/Resources/Assets.xcassets/EntryPlus.imageset/plus.svg) | 1,362 | `e29279e2ea58e5fd275d5fe683e8e874f34c63a800af14cdafcbd32f9ebcb20f` |
| [EntryBack/back.svg](../Researchers/Resources/Assets.xcassets/EntryBack.imageset/back.svg) | 854 | `1a92bf7a245cf55ac59745d295d15da25ec9a06532d4cf025ab14be63a03d40c` |

## Canvas와 원점 계산

모든 값은 pt입니다. SVG viewBox 원점과 실제 path bbox 원점은 모두 `(0,0)`입니다.
ceil 크기의 canvas에 작은 여백이 있으므로 canvas를 ink bbox 크기에 맞춰 축소·늘리지 않습니다.

| 아이콘 | SVG canvas·viewBox 크기 | 실제 path bbox | 프레임 안 SVG 원점 |
| --- | --- | --- | --- |
| gear | 25×25 | 24.7031×24.6865 | (345.6484375, 37.66357421875) |
| plus | 18×18 | 17.7222×17.7222 | (349.134765625, 758.1416015625) |
| back | 11×19 | 10.6084×18.5273 | (29.29296875, 79.7431640625) |

`SVG 원점 = Text.absoluteRenderBounds.origin − frame.absoluteBoundingBox.origin − pathBBox.origin`

버튼의 프레임 상대 bounds는 gear `(334,26,48,48)`, plus `(334,743,48,48)`,
back `(14,67,44,44)`입니다. 중앙 배치한 canvas에 아래 차이만 더합니다.

`중앙 배치 보정 = SVG 원점 − 버튼 원점 − (버튼 크기 − canvas 크기) / 2`

| 아이콘 | 버튼 내부 canvas 원점 | 중앙 배치 보정 (x,y) |
| --- | --- | --- |
| gear | (11.6484375, 11.66357421875) | (+0.1484375, +0.16357421875) |
| plus | (15.134765625, 15.1416015625) | (+0.134765625, +0.1416015625) |
| back | (15.29296875, 12.7431640625) | (−1.20703125, +0.2431640625) |

SVG 소수 직렬화와 API render bounds의 크기 차이는 최대0.001pt 미만입니다.
gear 버튼 전체의 −1/3pt 이동은 제거하고 배경 원점을 원본 y26으로 유지합니다.

## 명목 색상과 합성

gear leaf는 명목 `#1A1A1A`와 `LINEAR_BURN`, back은 같은 명목 색상과 상위 Text의
`LINEAR_BURN`을 사용합니다. plus는 white paint와 `LINEAR_DODGE`이며 SVG에도
`mix-blend-mode:plus-lighter`가 있습니다. 중성 아이콘의 실제 원본 core는 RGB17로 일정합니다.
현재 템플릿 Image는 합성된 색17/255와 `.normal`, 추가 버튼은 white와 `.plusLighter`로
매핑합니다. 명목26을 배경 그라데이션에 다시 burn하면 원본과 달리 core가13…22로 변합니다.
최종 합성색을 직접 적용한 뒤 원본 RGB17 좌표에서의 정확 일치가 gear88→1,251/1,299px,
back19→379/405px로 늘었습니다.
명목 색·blend 설정은 최종 화면의 RGBA와 구분합니다. 배경·그림자·AA를 포함한 합성 결과와
플랫폼 간 blend 동등성은 실제 원본 비교로 확인하며, 이번 출처 확인으로 확정하지 않습니다.

## 행 오른쪽 chevron

행의 chevron은 버튼 아이콘 세 개와 별도로 홈의 Text leaf `502:12307`에서 내보냈습니다.
원본은 SF Pro Regular, `wght=400`, `wdth=100`, 15pt입니다. 프레임은 홈 상대
`(371,387,11,20)`, 실제 render origin은 `(373.85595703125,390.3544921875)`이며
ink 크기는 `7.1630859375×12.71484375`입니다.

SVG의 `8×13` canvas·viewBox와 원점을 유지하고 `11×20` Text 프레임 안에서
중앙 배치 보정 `(+1.35595703125,−0.1455078125)`를 적용합니다. ink 크기로 canvas를
축소하지 않습니다. [EntryChevron/chevron.svg](../Researchers/Resources/Assets.xcassets/EntryChevron.imageset/chevron.svg)는
877bytes이며, 원본과 앱 자원의 동일 SHA256은
`62a87f40ea3e7d3167d8ba4ef86f93fa065c58050f7cf07cadd637068d7de55c`입니다.
XML은 path 하나이며 `preserves-vector-representation=true`를 사용합니다.

원본 SVG의 `fill="#3C3C43"`·`fill-opacity="0.6"`를 바이트 그대로 보존합니다.
템플릿 Image의 foreground는 불투명 `(60,60,67)`로 지정해 SVG의 alpha에0.6을
다시 곱하지 않습니다. 최종 RGB는 흰 배경에서 합성한 결과와 별도로 비교합니다.

## 표시 계층 경계와 검증

[EntryRoundButton](../Researchers/Features/ExperimentEntry/Presentation/EntryAppearance.swift)의
내부 `symbolImage`·`asset`이 template Image, canvas 크기와 원점 보정을 담당합니다.
버튼 배경·그림자·접근성·액션은 코드로 유지합니다. 이후 DS 적용 시 이 표시 내부를 교체하고
Feature·저장소·UUID delegate 계약을 유지합니다.
별도 QA 생성기는 `Researchers/Resources` 전체를 앱 그룹에 연결해 Assets와 Fonts를 함께 포함합니다.
원본 SVG·앱 SVG 바이트와 SHA256 일치, XML/path 구조를 읽기 전용으로 확인했습니다.
실제 빌드·화면 일치 결과는 [Entry 검증 절차](experiment-entry.md#시뮬레이터-검증)로 별도 확인합니다.

텍스트의 원본 대비 가로 잔여를 줄이기 위해 진행 중 배지를 제외한 배지 텍스트·등록 제목·
프로토콜 없이 진행 문구를 캡처 기준 왼쪽1px 보정했으며, 글꼴 크기와 세로 위치는 유지했습니다.

2026-10-28 iPhone 17 시뮬레이터에서 1206×2622 원본·캡처를 정렬·마스킹 없이 비교했습니다.
홈 MAE는0.100661199/255, 등록은0.059387148/255입니다. 0이 아닌 RGB 차이를 모두 세면
각각3.63074660%, 1.69569139%이며, 완전한 픽셀 일치로 표시하지 않습니다.

## 버튼 표면과 그림자

원본의 중성·추가 버튼에는 여러 fill과 GLASS 효과가 겹쳐 있습니다.
원본에 단일 gradient fill이 있다고 해석하지 않고, 흰 배경에서 실제 내보낸 색상 변화를
표시 계층에 매핑했습니다. 중성 표면은 topLeading238→bottomTrailing254이고,
추가 표면은 `(0,138,248) → (0,144,254) → (6,150,254)`의 세 색상입니다.
추가 표면은 [출력 색 공간 보간](https://developer.apple.com/documentation/swiftui/gradient/colorspace)을
명시한 `.colorSpace(.device)`를 사용합니다.

그림자는 black12%, offset `(0,8)`, SwiftUI radius17입니다. 원본 drop shadow의 radius40을
SwiftUI의 같은 숫자로 옮기지 않았습니다. 시뮬레이터에서20→17 변경 후 세 버튼 모두
가까운·먼 그림자 영역의 MAE가 줄었고, 추가 버튼 내부 색과 접근성 프레임은 그대로였습니다.
원본 유리 효과와 플랫폼 렌더러가 동일하다는 뜻은 아니며, 남은 차이도 전체 비교에 포함합니다.

추가 버튼 원주의 반사광도 원본 GLASS의 출력에서 측정했습니다. 원본에 별도 stroke가 있는 것은
아닙니다. 화면 좌표의 오른쪽을0도·아래를90도로 잡으면45도·225도에서 강하고135도·315도에서
약해집니다. 이를0.6pt `strokeBorder`, 최대 opacity0.43·0.63의 cos² angular gradient,
`plusLighter`로 표시합니다. 반사광은 그림자 계산 뒤에 합성하고 터치를 받지 않습니다.
이 순서에서 원주 밖 그림자·원주 띠를 제외한 버튼 내부·plus·접근성 프레임은 적용 전과 같고,
원주 RGB 오차가 줄었습니다. 이후 DS 교체 시 이 반사광도 `EntryRoundButton` 내부와 함께 대체합니다.
26차 대비 홈 MAE는0.112306507→0.103127573으로 줄었고, 다른 픽셀 수는116,334→116,340으로
6개 늘었습니다. 평균 오차 감소와 불일치 픽셀 증가를 함께 기록합니다.

중성 표면도 같은45도·225도 방향의 얇은 반사광을 가집니다. 기존 표면과 그림자를 유지하고,
0.8pt strokeBorder와 최대 opacity0.05·0.095의 cos² angular gradient를 그림자 뒤에 합성합니다.
32차 원주 MAE는 gear47.8%·back37.5% 줄었고, glyph·빈 내부·외부 그림자·추가 버튼·접근성
프레임은31차와 픽셀 단위로 같았습니다. 이 반사광도 원본 GLASS의 표현을 매핑한 것입니다.

## 카드와 배지의 모서리

원본의 카드 `502:12568`·`502:12598`·`502:12571`은 radius6/smoothing0,
홈 상태 배지7개는 radius4/smoothing0입니다. 이 값은 원본을 수정하지 않고 다시 읽었습니다.
두 역할에 `RoundedRectangle(style: .circular)`를 명시해 원형 모서리로 표시합니다.
다음 버튼 `502:12573`은 radius1000/smoothing0.6이므로 기존 Capsule을 유지했습니다.
33차 변경은 배지·카드의 모서리에만 발생했고, 모든 카드 모서리의 원본 오차가 줄었습니다.
첫 사진 카드의 왼쪽 위에는 뒤로 가기 그림자가 겹치므로 순백 배경의 모서리 모델과 구분합니다.
