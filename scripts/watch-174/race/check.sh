#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
work=$(mktemp -d -t labcord-watch-race)
trap 'rm -rf -- "$work"' EXIT

swiftc -emit-library -emit-module -module-name LabcordShared \
  "$script_dir/LabcordShared.swift" -emit-module-path "$work/LabcordShared.swiftmodule" \
  -o "$work/libLabcordShared.dylib"
swiftc -emit-library -emit-module -module-name LabcordWatchOS \
  -I "$work" -L "$work" -lLabcordShared "$script_dir/LabcordWatchOS.swift" \
  -emit-module-path "$work/LabcordWatchOS.swiftmodule" -o "$work/libLabcordWatchOS.dylib"
swiftc -emit-library -emit-module -module-name ComposableArchitecture \
  -I "$work" -L "$work" -lLabcordWatchOS "$script_dir/ComposableArchitecture.swift" \
  -emit-module-path "$work/ComposableArchitecture.swiftmodule" -o "$work/libComposableArchitecture.dylib"
swiftc -parse-as-library -I "$work" -L "$work" \
  -lLabcordShared -lLabcordWatchOS -lComposableArchitecture \
  -Xlinker -rpath -Xlinker "$work" \
  "$script_dir/Stubs.swift" \
  "$repo/ResearchWatchApp/Features/Recording/WatchRecordingUIBridge+Live.swift" \
  "$script_dir/RaceChecks.swift" -o "$work/race-checks"
"$work/race-checks"
