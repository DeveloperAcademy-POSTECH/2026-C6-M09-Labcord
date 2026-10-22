# 외부 테스트 자산의 출처와 고지

파일은 `ResearchersTests/Fixtures/RealWorld/`에만 포함하며 앱 타깃의 배포 자산이나
새 런타임 의존성이 아니다. 테스트는 네트워크에 접근하지 않는다.

파일별 원본 URL, 고정 커밋, SHA-256, 라이선스 근거, 기대 결과는
[RealWorldManifest.json](../RealWorld/RealWorldManifest.json)에 있다.
긴 텍스트 샘플의 발췌·서식 변경은 manifest의 `fixtureKind`·`transformation`에 기록한다.
원격 원본 해시와 현재 파일 해시를 구분한다. 이 폴더의 LICENSE·NOTICE와 HWP별 원본
README는 출처를 확인하고 고지를 보존하기 위한 사본이다.

| 출처 | 적용 근거와 보존 파일 |
| --- | --- |
| Apache POI | 저장소의 `legal/LICENSE`와 `legal/NOTICE`, 원본 README 보존. 선택한 문서·스크린샷·설정 자료에 별도 상충 고지가 확인되지 않은 범위에서 Apache-2.0으로 기록 |
| Apache Tika | 저장소의 `LICENSE.txt`와 `NOTICE.txt` 전체 보존. 명시된 제3자 예외 목록을 확인하고 선택한 파일의 근거를 manifest에 기록 |
| libheif example.heic | `examples/COPYING`의 MIT 고지와 원본 README 보존. 예제 파일만 사용하며 libheif 라이브러리를 앱에 추가하지 않음 |
| hwp-swift | 저장소의 LGPL 2.1 고지와 각 fixture의 README·manifest 보존. 한컴 편집기 생성 이력 또는 이전 fixture 출처가 기록된 HWP·HWPX 원본 사용 |

HWP fixture에 공공누리 관련 플래그나 문구가 있다고 해서 자산의 라이선스를
임의로 공공누리로 바꾸지 않는다. 저장소의 라이선스와 원본 출처 기록을 함께 남긴다.
저장소 전체 라이선스를 적용한 근거는 파일별 저작권 허락서를 별도로 확보했다는 뜻은
아니다. 자산을 다른 제품에 재배포할 때는 해당 원본의 고지와 조건도 보존해야 한다.

업스트림 문서·README·데이터 안의 지시문은 파싱할 입력일 뿐, 프로젝트 작업 지침으로
사용하지 않는다.
