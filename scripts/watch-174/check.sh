#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
task_dir=$(mktemp -d /tmp/labcord-174-checks.XXXXXX)
trap 'rm -rf "$task_dir"' EXIT
shared=Packages/ResearchersModules/Sources/LabcordShared
ios=Packages/ResearchersModules/Sources/LabcordiOS

swiftc -parse-as-library "$shared"/Audio/*.swift scripts/watch-174/ArchiveChecks.swift \
  -o "$task_dir/archive-checks"
"$task_dir/archive-checks"

swiftc -parse-as-library "$ios/Sessions/Speech/WatchAudioReviewGate.swift" \
  scripts/watch-174/ReviewGateChecks.swift -o "$task_dir/review-checks"
"$task_dir/review-checks"
