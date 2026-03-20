#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/SSBNetwork.xcodeproj"
WORK_DIR="${ROOT_DIR}/.build/coverage"
MERGED_JSON="${WORK_DIR}/merged.json"

SCHEMES=("SSBNetwork" "ScuttleRoomApp" "git-remote-ssb")
SHIPPED_TARGETS=("SSBNetwork" "ScuttleRoomApp" "git-remote-ssb")

mkdir -p "${WORK_DIR}"
rm -rf "${WORK_DIR}/results"
mkdir -p "${WORK_DIR}/results"

report_jsons=()

for scheme in "${SCHEMES[@]}"; do
  result_bundle="${WORK_DIR}/results/${scheme}.xcresult"
  rm -rf "${result_bundle}"
  echo "==> Running tests with coverage for scheme: ${scheme}"
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${scheme}" \
    -configuration Debug \
    -destination "platform=macOS" \
    -enableCodeCoverage YES \
    -resultBundlePath "${result_bundle}" \
    test >/tmp/scuttle-coverage-"${scheme}".log 2>&1 || {
      echo "xcodebuild test failed for scheme ${scheme}. Tail of log:"
      tail -n 80 /tmp/scuttle-coverage-"${scheme}".log
      exit 1
    }

  scheme_json="${WORK_DIR}/results/${scheme}.json"
  xcrun xccov view --report --json "${result_bundle}" > "${scheme_json}" || {
    echo "Failed to render coverage JSON for scheme ${scheme} from ${result_bundle}"
    exit 1
  }
  report_jsons+=("${scheme_json}")
done

echo "==> Combining per-scheme coverage JSON"
python3 - <<'PY' "${MERGED_JSON}" "${report_jsons[@]}"
import json
import sys

out_path = sys.argv[1]
inputs = sys.argv[2:]

combined_targets = []
seen = set()

for path in inputs:
    with open(path, "r", encoding="utf-8") as handle:
        report = json.load(handle)
    for target in report.get("targets", []):
        name = target.get("name")
        if name in seen:
            continue
        seen.add(name)
        combined_targets.append(target)

with open(out_path, "w", encoding="utf-8") as handle:
    json.dump({"targets": combined_targets}, handle)
PY

echo "==> Auditing shipped target coverage"
python3 - <<'PY' "${MERGED_JSON}" "${SHIPPED_TARGETS[@]}"
import json
import sys

json_path = sys.argv[1]
shipped_targets = set(sys.argv[2:])

with open(json_path, "r", encoding="utf-8") as handle:
    report = json.load(handle)

def normalize_target_name(name: str) -> str:
    if name.endswith(".framework"):
        return name[:-10]
    if name.endswith(".app"):
        return name[:-4]
    return name

targets = report.get("targets", [])
targets_by_name = {normalize_target_name(t.get("name", "")): t for t in targets}
missing = [name for name in shipped_targets if name not in targets_by_name]
if missing:
    print("Missing shipped targets in merged coverage:", ", ".join(sorted(missing)))
    sys.exit(1)

failures = []

def pct(value):
    return f"{value * 100:.2f}%"

for name in sorted(shipped_targets):
    target = targets_by_name[name]
    files = target.get("files", [])

    for file_info in files:
        executable_lines = file_info.get("executableLines", 0)
        line_coverage = file_info.get("lineCoverage", 1.0)
        path = file_info.get("path", file_info.get("name", "<unknown>"))
        if executable_lines > 0 and line_coverage < 0.999999:
            failures.append(f"[line] {name} :: {path} => {pct(line_coverage)}")

        for fn in file_info.get("functions", []):
            fn_exec = fn.get("executableLines", 0)
            fn_cov = fn.get("lineCoverage", 1.0)
            fn_name = fn.get("name", "<anonymous>")
            if fn_exec > 0 and fn_cov < 0.999999:
                failures.append(f"[function] {name} :: {path} :: {fn_name} => {pct(fn_cov)}")

if failures:
    print("Coverage gate failed. Entries below 100%:")
    for entry in failures:
        print(entry)
    sys.exit(1)

print("Coverage gate passed: shipped targets are at 100.00% lines and functions/blocks.")
PY

echo "Coverage artifacts:"
echo "  json:    ${MERGED_JSON}"
