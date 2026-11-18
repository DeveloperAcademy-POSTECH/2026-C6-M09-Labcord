#!/bin/bash
# 녹화 진행 큐. 앱 데이터를 지우거나 자동으로 기록을 생성하지 않는다.
set -euo pipefail

mode=${1:---interactive}
if [[ "$mode" != --interactive && "$mode" != --dry-run ]]; then
  printf '사용법: %s [--interactive|--dry-run]\n' "$0" >&2
  exit 2
fi

if [[ "$mode" == --interactive ]]; then
  : "${LABCORD_AGENT_DEVICE:?device_open이 반환한 agent-device 경로를 지정하세요}"
  [[ -x "$LABCORD_AGENT_DEVICE" ]] || { printf 'agent-device를 실행할 수 없습니다.\n' >&2; exit 2; }
fi

cue() {
  printf '\n%s\n' "$1"
  if [[ "$mode" == --interactive ]]; then
    printf '완료하고 화면을 확인한 뒤 Enter를 누르세요. 중단하려면 Ctrl-C: '
    read -r _
  fi
}

checkpoint() {
  local expected=$1
  printf '화면 확인: %s\n' "$expected"
  if [[ "$mode" == --interactive ]]; then
    # 오류 출력과 종료 코드를 그대로 남기고 이후 큐를 실행하지 않는다.
    "$LABCORD_AGENT_DEVICE" wait text "$expected" 45000
  fi
}

cue '[오프닝] 기록 때문에 놓치는 실험의 순간이 없도록. 두 손은 실험에, 기록은 랩코드에.'
cue '[시작 확인] 기존 촬영 자료를 유지할 때는 백업 후 -LabcordPreserveSimulatorExperiments 인수로 앱을 실행한다. 새 세션을 초기화해 시작할 때는 인수를 생략하고 비어 있는 홈을 확인한다.'
cue '[등록] 홈의 +를 누르고 최근 파일에서 Labcord 화학실험 프로토콜 v3 PDF를 선택한다. 분석이 끝날 때까지 기다린다.'
cue '[검토] 추출된 타이머와 용어를 보여 주고 확인한다. 실험 등록을 완료한다.'
cue '[실험 화면] Labcord 실험을 열고 카메라 화면과 타이머 패널이 보이는지 확인한다.'
checkpoint '타이머'
cue '[iPhone 음성 V03] 영상 선택에서 V03을 재생한다. 자동으로 녹음 중이 뜨고 준비된 전사가 표시되면 충분히 기다린 뒤 녹음을 종료하고 결과를 확인한다.'
cue '[iPhone 사진 V04] 영상 선택에서 V04를 재생한다. 자동 촬영 카운트다운과 영상 프레임이 담긴 미리보기를 확인한다.'
cue '[iPhone 영상 V05] 영상 선택에서 V05를 재생한다. 영상 녹화 중과 경과 시간을 확인하고 종료 후 미리보기를 촬영한다. 현재 결과물은 초록색이다.'
cue '[Watch 장면 음성 V06-A] V06-A를 선택하면 W02_double_pinch.mp4가 재생된다. 두 번째 핀치를 뗀 25프레임에 iPhone 음성 기록이 실행되고 발화 장면이 이어진다. 녹음 중 실시간 전사 문장이 표시되지 않는지 확인한다. 종료 후 미리보기에서 두 번째 대본 두 문장을 확인한다. 해당 파일이 없으면 V06-A 버튼은 비활성화된다.'
cue '[Watch 장면 사진 V07] V07을 선택하면 W03_single_fist.mp4가 재생되고 주먹인 28프레임에 iPhone 사진이 실행된다. 카운트다운과 미리보기를 확인한다.'
cue '[Watch 장면 영상 V08] V08을 선택하면 W04_double_fist.mp4가 재생되고 두 번째 주먹인 35프레임에 iPhone 영상이 실행된다. 녹화 상태와 미리보기를 확인한다.'
cue '[타이머 V12] 프로토콜에서 등록한 타이머와 설정된 타이머 탭을 확인하고 V12를 재생한다. 첫 타이머의 자동 실행 상태를 확인한다.'
cue '[결과] 홈에서 숨겨진 시연 결과 준비 접근성 버튼을 누르고 시연 결과 준비 완료를 확인한다. 최근 실험을 열어 전체 유형의 시간순 기록을 천천히 스크롤한다.'
cue '[클로징] 연구의 순간을 하나의 기록으로. 랩코드.'
printf '\n큐 종료. 각 수동 조작·iPhone 동작·저장 결과의 성공 여부는 별도로 확인하세요.\n'
