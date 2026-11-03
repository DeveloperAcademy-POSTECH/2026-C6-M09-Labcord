# 기존 압축본 대조 자료

검증 담당자가 기존 저장 산출물에서 추출한 `reference.json`을 이 디렉터리에 놓으면
`R117ReferenceTests`가 같은 본문의 후보·shortlist·seed42 final50을 대조합니다.
참조 원문과 용어 목록은 저장소에 커밋하지 않습니다. 파일이 없으면 4개 테스트는 XCTSkip입니다.
일반 규칙·전체 실행 테스트 13개 통과와 원본 대조 통과를 구분해 보고합니다.
새 앱 추론 결과를 golden으로 사용하지 않습니다.

최상위 필드:

- `text: String`, `language: String`, `expectedTerms: [String]`
- `feature_rows: [{text: String, start: Int, end: Int}]` — 원본 Unicode scalar 좌표
- `canonical_pool_record.rawCandidates: [{start, end, score, kind, tier, retained}]`
- `canonical_pool_record.native`, `canonical_pool_record.guarded`: `[{text: String}]`

실제 QA 파일은 원본 파일별 SHA-256과 저장된 기존 점수·후보 좌표도 보존합니다.
2026-11-02 v2 SHA-256은
`1e27ffc7b42aa8bdec488c40f3c80fac61800c290ac35a4d331380b3c59be1f0`입니다.
이 파일에서 저장된 canonical pool의 grouping은 일치하지만, fresh pool과 final50 순서
테스트는 실패합니다. 원인·범위는 docs/protocol-term-integration.md에 기록합니다.
