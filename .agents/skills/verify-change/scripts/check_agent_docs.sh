#!/usr/bin/env bash
# Optional document checks using Bash 3.2+ and standard macOS/Linux tools.
# Checks our metadata convention and simple inline file links, not full YAML,
# Markdown anchors, external URLs, agent discovery, or application behavior.
set -eu

if [ "$#" -gt 1 ]; then
    printf 'Usage: bash %s [repository-root]\n' "$0" >&2
    exit 2
fi
root=$(cd "${1:-$(dirname "$0")/../../../..}" && pwd -P)
failures=0
skills=0
documents=("$root/AGENTS.md" "$root/docs/agent-rules.md")

fail() {
    printf '%s\n' "$1" >&2
    failures=$((failures + 1))
}

for directory in "$root"/.agents/skills/*; do
    [ -d "$directory" ] || continue
    skills=$((skills + 1))
    file="$directory/SKILL.md"
    name=${directory##*/}
    documents+=("$file")
    if [ ! -f "$file" ]; then
        fail "$file: missing SKILL.md"
        continue
    fi
    if ! awk -v expected="$name" '
        NR == 1 { if ($0 != "---") exit 1; next }
        $0 == "---" { closed = 1; exit }
        /^name: / { name = substr($0, 7); names++; next }
        /^description: / { description = substr($0, 14); descriptions++; next }
        { invalid = 1 }
        END {
            indicators = "|>\"[{#&*!%" sprintf("%c", 39)
            if (!closed || invalid || names != 1 || descriptions != 1 ||
                name != expected || length(name) > 64 ||
                name !~ /^[a-z0-9]+(-[a-z0-9]+)*$/ ||
                description !~ /[^[:space:]]/ ||
                description ~ /^[[:space:]]|[[:space:]]$/ ||
                index(indicators, substr(description, 1, 1)) ||
                description ~ /: | #/ ||
                description ~ /^(null|Null|NULL|~|true|True|TRUE|false|False|FALSE)$/ ||
                description ~ /^[-+]?[0-9]+([.][0-9]+)?$/) exit 1
        }
    ' "$file"; then
        fail "$file: invalid name/description frontmatter"
    fi
    description=$(awk 'NR == 1 { next } $0 == "---" { exit } /^description: / { print substr($0, 14) }' "$file")
    if [ "$(printf '%s' "$description" | wc -m)" -gt 1024 ]; then
        fail "$file: description exceeds 1024 characters"
    fi
    for section in '## 사용 시점' '## 팀 규칙' '## 절차' '## 주의사항과 예외' '## 결과 검증'; do
        if ! grep -Fqx "$section" "$file"; then
            fail "$file: missing section $section"
        fi
    done
    if ! grep -Fq ".agents/skills/$name/SKILL.md" "$root/AGENTS.md"; then
        fail "$file: not linked from AGENTS.md"
    fi
done
[ "$skills" -gt 0 ] || fail '.agents/skills: no Skill directories found'

for file in "${documents[@]}"; do
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        fail "$file: missing or unreadable document"
        continue
    fi
    while IFS= read -r target; do
        case "$target" in
            *:*|//*|\#*) continue ;;
        esac
        target=${target%%#*}
        [ -n "$target" ] || continue
        if [ "${target#/}" != "$target" ]; then
            fail "$file: file link must be relative: $target"
            continue
        fi
        if ! parent=$(cd "$(dirname "$file")/$(dirname "$target")" 2>/dev/null && pwd -P); then
            fail "$file: broken local file link $target"
            continue
        fi
        case "$parent" in
            "$root"|"$root"/*) ;;
            *) fail "$file: file link escapes repository: $target"; continue ;;
        esac
        [ -f "$parent/$(basename "$target")" ] || fail "$file: broken local file link $target"
    done < <(awk '
        {
            remaining = $0
            while (match(remaining, /\[[^]]+\]\([^)]*\)/)) {
                link = substr(remaining, RSTART, RLENGTH)
                remaining = substr(remaining, RSTART + RLENGTH)
                sub(/^[^(]*\(/, "", link)
                sub(/\)$/, "", link)
                print link
            }
        }
    ' "$file")
done

if [ "$failures" -ne 0 ]; then
    printf 'Agent document checks FAILED (%s errors)\n' "$failures" >&2
    exit 1
fi
printf 'Agent document checks PASSED (metadata, sections, index, local file links)\n'
