#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
task_dir=$(mktemp -d /tmp/labcord-phone-snapshot.XXXXXX)
trap 'rm -rf "$task_dir"' EXIT
swiftc -parse-as-library \
  Packages/ResearchersModules/Sources/LabcordiOS/WatchConnectivity/Clients/WatchSnapshotPublicationPolicy.swift \
  scripts/watch-173/PhoneSnapshotPublicationChecks.swift -o "$task_dir/checks"
"$task_dir/checks"
