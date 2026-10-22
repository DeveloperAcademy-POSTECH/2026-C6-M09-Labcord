# 파싱 검증 자산

테스트 파일과 라이선스 고지를 먼저 모았습니다. 파서와 테스트 코드는 뒤의 PR에서 연결합니다.
앱과 테스트는 저장소에 포함한 파일을 사용하며 원격 파일을 자동 다운로드하지 않습니다.

- `RealWorld/`: 형식별 샘플 60개와 대용량 PDF 3개
- `RealWorld/RealWorldManifest.json`: 출처·고정 커밋·라이선스·현재 파일 해시와 크기
- `RealWorld/GoldenAssertions.json`: 부분 정답·표 셀·순서·이미지 기대값
- `Licenses/`: 변경하지 않은 외부 LICENSE·NOTICE·원본 README와 출처 안내
- 루트의 Office·HWP 파일: 자체 생성한 본문·표·삽입 이미지 샘플

긴 텍스트 샘플은 검증 구간을 발췌했습니다. JSON 일부는 값 전체를 보존하고 서식만 줄였습니다.
변경한 파일은 manifest의 `fixtureKind`와 `transformation`에 표시합니다. `originalSHA256`·
`originalSizeBytes`는 원격 원본, `sha256`·`sizeBytes`는 저장소의 현재 파일을 가리킵니다.
원본 출처·라이선스 고지와 기존 텍스트·표·이미지 검증 조건은 유지했습니다.
바이너리·HTML 내장 이미지·RTF 파일은 수정하지 않았습니다. 전체 원문을 검증한 과거 성능 수치를
발췌본의 성능으로 해석하면 안 됩니다. 검증 로그와 대형 측정 JSON은 포함하지 않습니다.
