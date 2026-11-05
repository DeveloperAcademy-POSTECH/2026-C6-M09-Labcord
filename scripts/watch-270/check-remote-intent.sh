#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
task_dir=$(mktemp -d "${TMPDIR:-/tmp}/labcord-remote-intent.XXXXXX")
trap 'rm -rf "$task_dir"' EXIT
swiftc -emit-module -emit-library -module-name LabcordShared \
  "$repo_dir/Packages/ResearchersModules/Sources/LabcordShared/Messages/WatchRemoteIntentMessage.swift" \
  -emit-module-path "$task_dir/LabcordShared.swiftmodule" -o "$task_dir/libLabcordShared.dylib"
swiftc -parse-as-library -I "$task_dir" -L "$task_dir" -lLabcordShared \
  "$repo_dir/ResearchWatchApp/Intents/WatchRemoteIntentReceiver.swift" \
  "$script_dir/RemoteIntentChecks.swift" -o "$task_dir/check"
DYLD_LIBRARY_PATH="$task_dir${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" "$task_dir/check"
