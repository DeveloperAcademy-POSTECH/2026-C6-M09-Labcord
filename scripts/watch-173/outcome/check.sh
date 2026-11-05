#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
task_dir=$(mktemp -d /tmp/labcord-watch-outcome.XXXXXX)
trap 'rm -rf "$task_dir"' EXIT
python3 - "$task_dir/Checks.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Packages/ResearchersModules/Sources/LabcordiOS/WatchConnectivity/Clients/PhoneWatchExperimentCoordinator.swift').read_text()
execute = source[source.index('    func execute(_ command:'):source.index('    func snapshot(_ id:')]
request_status = source[source.index('    func requestStatus(_ command:'):source.index('    func execute(_ command:')]
unknown = source[source.index('    func unknownOutcome('):source.index('    func persistPendingStart()')]
conservative = source[source.index('    func conservativeMediaResult('):source.index('\n}\n\nprivate extension', source.index('    func conservativeMediaResult('))]
recovery = Path('Packages/ResearchersModules/Sources/LabcordiOS/WatchConnectivity/Clients/PhoneWatchExperimentCoordinator+OutcomeRecovery.swift').read_text()
recovery = recovery.replace('import Foundation\n', '').replace('import LabcordShared\n', '')
recovery = recovery.replace('PhoneWatchExperimentCoordinator', 'Coordinator')
template = Path('scripts/watch-173/outcome/CoordinatorOutcomeChecks.swift').read_text()
template = template.replace('    // ACTUAL_EXECUTE', execute).replace('    // ACTUAL_UNKNOWN_OUTCOME', unknown)
template = template.replace('    // ACTUAL_REQUEST_STATUS', request_status)
template = template.replace('    // ACTUAL_CONSERVATIVE_MEDIA_RESULT', conservative)
Path(sys.argv[1]).write_text(template.replace('// ACTUAL_OUTCOME_RECOVERY', recovery))
PY
swiftc -parse-as-library "$task_dir/Checks.swift" -o "$task_dir/checks"
"$task_dir/checks"
python3 - "$task_dir/HomeChecks.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Researchers/App/AppFeature+Watch.swift').read_text()
context = source[source.index('    var watchContextReducer:'):source.index('    func finishWatchRequest(')]
context = context.replace('some Reducer<State, Action>', 'Reduce<State, Action>')
start = source.index('    func openWatchSession(')
end = source.index('\n\n}', start)
open_session = source[start:end]
context = context.replace(r'case: \.session]', r'case: \.sessionValue]')
open_session = open_session.replace(r'case: \.session]', r'case: \.sessionValue]')
template = Path('scripts/watch-173/outcome/HomeTransitionChecks.swift').read_text()
Path(sys.argv[1]).write_text(template.replace('    // ACTUAL_CONTEXT_REDUCER', context).replace('    // ACTUAL_OPEN_WATCH_SESSION', open_session))
PY
swiftc -parse-as-library "$task_dir/HomeChecks.swift" -o "$task_dir/home-checks"
"$task_dir/home-checks"
python3 - "$task_dir/PreCaptureChecks.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Packages/ResearchersModules/Sources/LabcordiOS/WatchConnectivity/Clients/PhoneWatchExperimentCoordinator+Records.swift').read_text()
helper = source[source.index('    private func isPreCaptureRejection('):source.index('    private func shouldApplyTimerDirectly(')]
template = Path('scripts/watch-173/outcome/PreCaptureChecks.swift').read_text()
Path(sys.argv[1]).write_text(template.replace('    // ACTUAL_PRE_CAPTURE_CLASSIFICATION', helper.replace('private func', 'func')))
PY
swiftc -parse-as-library "$task_dir/PreCaptureChecks.swift" -o "$task_dir/pre-capture-checks"
"$task_dir/pre-capture-checks"
python3 - "$task_dir/DispatchChecks.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Packages/ResearchersModules/Sources/LabcordiOS/WatchConnectivity/Clients/PhoneWatchExperimentCoordinator+Execution.swift').read_text()
method = source[source.index('    private func executeRecordHandler('):source.index('    func start(_ command:')].replace('private func', 'func')
template = Path('scripts/watch-173/outcome/DispatchChecks.swift').read_text()
Path(sys.argv[1]).write_text(template.replace('    // ACTUAL_HANDLER', method))
PY
swiftc -parse-as-library "$task_dir/DispatchChecks.swift" -o "$task_dir/dispatch-checks"
"$task_dir/dispatch-checks"
python3 - "$task_dir/CloseChecks.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Packages/ResearchersModules/Sources/LabcordiOS/WatchConnectivity/Clients/PhoneWatchExperimentCoordinator+Execution.swift').read_text()
method = source[source.index('    func close('):source.rindex('\n}')]
template = Path('scripts/watch-173/outcome/CloseChecks.swift').read_text()
Path(sys.argv[1]).write_text(template.replace('    // ACTUAL_CLOSE', method))
PY
swiftc -parse-as-library "$task_dir/CloseChecks.swift" -o "$task_dir/close-checks"
"$task_dir/close-checks"
