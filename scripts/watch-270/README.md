# Watch 원격 Intent 수신 집중 검사

저장소 루트에서 `sh scripts/watch-270/check-remote-intent.sh`를 실행한다.
실제 공유 메시지 DTO와 Watch 수신기를 컴파일하고 가짜 Intent runtime으로 요청 ID 중복,
충돌, 만료, 성공·실패 전달과 직렬화를 확인한다. WatchConnectivity, 실제 마이크와 기기 실행,
영구 저장 또는 앱 프로세스 재시작은 이 검사 범위에 포함되지 않는다.
