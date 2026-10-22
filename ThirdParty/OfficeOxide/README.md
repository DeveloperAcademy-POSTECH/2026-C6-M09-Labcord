# OfficeOxide

- office_oxide 0.1.15, 커밋 `5d183f4de990de254f32976bf952e548bcd25972`. MIT 라이선스를 선택했다. 원본 LICENSE-MIT·NOTICE와 앱 리소스의 전이 의존성 고지를 보존한다.
- DOC·PPT 본문/표용 정적 XCFramework. iOS arm64, Simulator arm64/x86_64를 포함한다. XLS/XLSX·OOXML과 OfficeArt 그림 복구는 기존 구현을 사용한다.
- C 핸들과 반환 문자열은 호출 내에서 해제한다. 라이브러리가 그림 payload를 중복 생성하지 않도록 호환 패치를 적용했다.
- 패치는 원래 지원하던 단일 행·열/병합 PPT 표와 3% 영역 판정 기준을 유지한다. 일반 upstream 2×2 표 판정 정책과 차이가 있다.
- 재빌드: Rust iOS 타깃 세 개가 설치된 환경에서 `bash build.sh`. 앱·CI 빌드에는 Rust나 추가 다운로드가 필요 없다.
- 제공 바이너리는 Homebrew Rust 1.97.1에서 `RUSTC_BOOTSTRAP=1`과 `-Z build-std=std,panic_abort`로 표준 라이브러리를 소스 빌드했다. 원본 리비전·Cargo.lock·compat.patch를 고정한다.
- `SHA256SUMS`는 포함된 정적 라이브러리의 SHA-256이다. 앱 iOS 27.0과 Swift 언어 모드 5.0은 바꾸지 않는다.
