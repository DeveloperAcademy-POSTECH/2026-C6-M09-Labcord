#!/usr/bin/env bash
set -euo pipefail
shopt -s nocasematch
paths_file=$(mktemp)
trap 'rm -f "$paths_file"' EXIT

build=false
lint=false
count=0
reason='문서·협업 설정만 변경'
separator=..
if [[ "$IS_PR" == true ]]; then
  separator=...
fi

# 파일로 받아 git diff의 실패를 직접 확인하고 NUL 구분 경로를 보존합니다.
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
      *.swift)
        build=true
        lint=true
        reason='문서·협업 및 lint 전용 변경 외: 두 검사 실행'
        ;;
      .gitignore|*/.gitignore|docs/*|.github/issue_template/*|*.md|*.mdx|*.rst|\
      .github/codeowners|.coderabbit.yaml|.coderabbit.yml|\
      .github/workflows/auto-assign.yml|.github/workflows/main-branch-guard.yml)
        ;;
      *)
        build=true
        lint=true
        reason='문서·협업 및 lint 전용 변경 외: 두 검사 실행'
        ;;
    esac
  done < "$paths_file"
else
  echo '::warning::Changed-file detection failed; running Build and SwiftLint.'
  build=true
  lint=true
  count='확인 불가'
  reason='변경 범위를 확인할 수 없어 두 검사 실행'
fi

printf 'build=%s\nlint=%s\n' "$build" "$lint" >> "$GITHUB_OUTPUT"
{
  printf '## 변경 파일 기준 CI 실행\n\n변경 경로 수: %s\n\n' "$count"
  printf '판별: %s\n\n' "$reason"
  printf '| 검사 | 실행 여부 |\n| --- | --- |\n'
  printf '| Build | %s |\n| SwiftLint | %s |\n' "$build" "$lint"
} >> "$GITHUB_STEP_SUMMARY"
