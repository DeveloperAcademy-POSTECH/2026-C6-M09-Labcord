#!/usr/bin/env bash
# 입력: BASE_SHA·HEAD_SHA는 비교할 커밋, IS_PR=true는 PR 이벤트입니다.
# 출력: GITHUB_OUTPUT에 build/lint=true|false를 기록해 후속 job 실행 여부를 전달하고,
# GITHUB_STEP_SUMMARY에는 사람이 확인할 판별 결과를 남깁니다.
set -euo pipefail
# 기존 경로 분류처럼 대소문자를 구분하지 않습니다.
shopt -s nocasematch

# 프로세스 치환으로 읽으면 git의 실패를 놓칠 수 있어 임시 파일에 먼저 받습니다.
# 임시 파일 생성 등 스크립트 자체가 실패해도 후속 job의 실패 대비 조건으로 검사를 실행합니다.
paths_file=$(mktemp)
trap 'rm -f "$paths_file"' EXIT

# 문서·협업 변경은 둘 다 생략, lint 전용 변경은 lint만, 나머지는 둘 다 실행합니다.
# 여러 파일의 결과는 합산하며, 한 번 true가 된 검사는 다른 파일 때문에 취소하지 않습니다.
build=false
lint=false
count=0
reason='문서·협업 설정만 변경'
# PR은 공통 조상부터 head까지 비교해 이전 커밋의 변경도 포함하고 base 쪽 새 변경은 제외합니다.
# push는 이벤트의 before와 현재 커밋 사이를 직접 비교합니다.
separator=..
if [[ "$IS_PR" == true ]]; then
  separator=...
fi

# 누락되거나 잘못된 SHA와 신규 브랜치 push의 0 SHA는 정상 비교로 취급하지 않습니다.
# git diff가 일부 경로를 출력한 뒤 실패해도 if에서 종료 상태를 확인하므로 생략으로 오판하지 않습니다.
# -z는 공백·개행을 포함한 경로를 보존하고, --no-renames는 rename의 이전·새 경로를 모두 판별합니다.
if [[ "${BASE_SHA:-}" =~ ^[0-9a-fA-F]{40,64}$ && ! "$BASE_SHA" =~ ^0+$ &&
      "${HEAD_SHA:-}" =~ ^[0-9a-fA-F]{40,64}$ && ! "$HEAD_SHA" =~ ^0+$ ]] &&
   git diff --name-only --no-renames -z "$BASE_SHA$separator$HEAD_SHA" > "$paths_file"; then
  while IFS= read -r -d '' path; do
    count=$((count + 1))
    case "$path" in
      .github/workflows/swiftlint.yml|.swiftlint.yml|.swiftlint.yaml|*/.swiftlint.yml|*/.swiftlint.yaml)
        lint=true
        if [[ "$build" == false ]]; then
          reason='SwiftLint 설정 또는 워크플로 변경'
        fi
        ;;
      # docs 안의 Swift 파일도 문서 예외보다 먼저 처리합니다. 작성자·커밋 메시지로 제외하지 않습니다.
      *.swift)
        build=true
        lint=true
        reason='문서·협업 및 lint 전용 변경 외: 두 검사 실행'
        ;;
      # 명시한 문서·협업 경로만 생략합니다. 앞서 다른 파일이 요구한 검사는 그대로 유지합니다.
      .gitignore|*/.gitignore|docs/*|.github/issue_template/*|*.md|*.mdx|*.rst|\
      .github/codeowners|.coderabbit.yaml|.coderabbit.yml|\
      .github/workflows/auto-assign.yml|.github/workflows/main-branch-guard.yml)
        ;;
      # 프로젝트·리소스·알 수 없는 파일은 모두 검사합니다. 이 스크립트 자체의 변경도 여기에 포함됩니다.
      *)
        build=true
        lint=true
        reason='문서·협업 및 lint 전용 변경 외: 두 검사 실행'
        ;;
    esac
  done < "$paths_file"
else
  # 비교할 수 없으면 두 검사를 실행해, 변경 목록을 모른다는 이유로 검사가 누락되지 않게 합니다.
  echo '::warning::Changed-file detection failed; running Build and SwiftLint.'
  build=true
  lint=true
  count='확인 불가'
  reason='변경 범위를 확인할 수 없어 두 검사 실행'
fi

# 후속 job이 읽을 키와 불리언 형식을 고정하고, 판별 이유는 Actions Summary에서 확인하게 합니다.
printf 'build=%s\nlint=%s\n' "$build" "$lint" >> "$GITHUB_OUTPUT"
{
  printf '## 변경 파일 기준 CI 실행\n\n변경 경로 수: %s\n\n' "$count"
  printf '판별: %s\n\n' "$reason"
  printf '| 검사 | 실행 여부 |\n| --- | --- |\n'
  printf '| Build | %s |\n| SwiftLint | %s |\n' "$build" "$lint"
} >> "$GITHUB_STEP_SUMMARY"
