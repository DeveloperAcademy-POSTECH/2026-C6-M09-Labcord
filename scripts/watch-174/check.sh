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

swiftc -emit-module -emit-library -module-name LabcordShared \
  "$shared/Models/ExperimentStatus.swift" "$shared/Models/ExperimentMode.swift" \
  "$shared"/Timers/*.swift \
  "$shared"/Messages/WatchExperiment*.swift "$shared/Messages/WatchRecordSnapshot.swift" \
  -emit-module-path "$task_dir/LabcordShared.swiftmodule" -o "$task_dir/libLabcordShared.dylib"
swiftc -parse-as-library -I "$task_dir" -L "$task_dir" -lLabcordShared \
  -Xlinker -rpath -Xlinker "$task_dir" "$ios/Sessions/WatchTimerMutation.swift" \
  scripts/watch-174/ContractChecks.swift \
  -o "$task_dir/contract-checks"
"$task_dir/contract-checks"

swiftc -parse-as-library "$ios/Sessions/Speech/WatchAudioReviewGate.swift" \
  scripts/watch-174/ReviewGateChecks.swift -o "$task_dir/review-checks"
"$task_dir/review-checks"
