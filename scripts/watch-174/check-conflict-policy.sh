#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
task_dir=$(mktemp -d /tmp/labcord-conflict-check.XXXXXX)
trap 'rm -rf "$task_dir"' EXIT

swiftc -emit-module -emit-library -module-name LabcordShared \
  Packages/ResearchersModules/Sources/LabcordShared/Messages/WatchExperimentCommand.swift \
  -emit-module-path "$task_dir/LabcordShared.swiftmodule" -o "$task_dir/libLabcordShared.dylib"
swiftc -parse-as-library -I "$task_dir" -L "$task_dir" -lLabcordShared \
  -Xlinker -rpath -Xlinker "$task_dir" \
  Packages/ResearchersModules/Sources/LabcordiOS/WatchConnectivity/Clients/WatchExperimentConflictPolicy.swift \
  scripts/watch-174/ConflictPolicyChecks.swift -o "$task_dir/conflict-checks"
"$task_dir/conflict-checks"
