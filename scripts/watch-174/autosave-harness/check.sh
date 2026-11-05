#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
task_dir=$(mktemp -d /tmp/labcord-record-autosave.XXXXXX)
trap 'rm -rf "$task_dir"' EXIT

mkdir -p "$task_dir/Sources/LabcordShared" "$task_dir/Sources/LabcordWatchOS" \
  "$task_dir/Sources/WatchScreens" "$task_dir/Tests/WatchScreensTests"
cp "$script_dir/Package.swift" "$task_dir/Package.swift"
cp "$script_dir/WatchExperimentClient.swift" "$task_dir/Sources/LabcordWatchOS/"
cp "$script_dir/IntentRuntimeLiveBoundary.swift" "$task_dir/Sources/WatchScreens/"
cp "$repo_dir/scripts/watch-174/WatchRecordAutoSaveTests.swift" \
  "$task_dir/Tests/WatchScreensTests/"
cp "$repo_dir/scripts/watch-174/WatchIntentRuntimeTests.swift" \
  "$task_dir/Tests/WatchScreensTests/"

shared="$repo_dir/Packages/ResearchersModules/Sources/LabcordShared"
for file in Models/ExperimentMode.swift Models/ExperimentStatus.swift Audio/WatchAudioMessage.swift \
  Messages/WatchExperimentCommand.swift Messages/WatchExperimentResponse.swift \
  Messages/WatchExperimentSnapshot.swift Messages/WatchRecordSnapshot.swift; do
  ln -s "$shared/$file" "$task_dir/Sources/LabcordShared/$(basename "$file")"
done

experiment="$repo_dir/ResearchWatchApp/Features/Experiment"
for file in WatchExperimentAuthorization WatchExperimentError+Presentation \
  WatchExperimentFeature+Intents WatchExperimentFeature WatchExperimentLifecycle \
  WatchExperimentPendingRecovery WatchExperimentPhotoCancellation WatchExperimentRequests \
  WatchExperimentStart WatchExperimentTools WatchMicrophonePermission WatchPendingRequestJournal \
  WatchPresentationRules WatchRequestPolicy; do
  ln -s "$experiment/$file.swift" "$task_dir/Sources/WatchScreens/$file.swift"
done
for file in WatchRecordFeature WatchRecordPresentation; do
  ln -s "$repo_dir/ResearchWatchApp/Features/Recording/$file.swift" \
    "$task_dir/Sources/WatchScreens/$file.swift"
done
ln -s "$repo_dir/ResearchWatchApp/Intents/WatchIntentRuntime.swift" \
  "$task_dir/Sources/WatchScreens/WatchIntentRuntime.swift"

# 선택적 로컬 빌드 캐시 복제는 원본 캐시를 수정하지 않는다.
if [ -n "${LABCORD_AUTOSAVE_BUILD_CACHE:-}" ]; then
  cp -cR "$LABCORD_AUTOSAVE_BUILD_CACHE" "$task_dir/.build"
fi

if swift test --package-path "$task_dir" --filter 'WatchRecordAutoSaveTests|WatchIntentRuntimeTests' \
  > "$task_dir/test.log" 2>&1; then
  grep -E "Test Case .* (started|passed)|Executed [0-9]+ tests" "$task_dir/test.log"
else
  tail -n 80 "$task_dir/test.log"
  exit 1
fi
