#!/usr/bin/env python3

import os
import sys
import subprocess
import json
import shutil
from pathlib import Path

def run_command(cmd, cwd=None):
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if result.returncode != 0:
        print(f"Command failed: {' '.join(cmd)}")
        print(f"Stdout:\n{result.stdout}")
        print(f"Stderr:\n{result.stderr}")
        sys.exit(result.returncode)
    return result.stdout

def build_and_test(scheme, result_path):
    cmd = [
        "xcodebuild", "test",
        "-scheme", scheme,
        "-destination", "platform=macOS",
        "-enableCodeCoverage", "YES",
        "-resultBundlePath", str(result_path)
    ]
    # We allow tests to fail because we want to see coverage regardless for debugging, 
    # but strictly speaking, if tests fail, we should probably fail. We'll fail if xcodebuild returns != 0
    # Wait, the prompt says: "Success means two hard gates: all test suites green, and merged coverage at 100.00%"
    # So if xcodebuild fails (test failed), this will exit via run_command.
    print(f"Running tests for scheme: {scheme}")
    # Don't capture output to allow real-time viewing of test logs, but xcodebuild output might be verbose.
    # Actually, we use capture_output=True in run_command, which hides it until failure. Let's do a custom run.
    print(f"Command: {' '.join(cmd)}")
    result = subprocess.run(cmd, text=True)
    if result.returncode != 0:
        print(f"Test suite '{scheme}' failed. See xcodebuild output above.")
        sys.exit(result.returncode)

def main():
    root_dir = Path(__file__).parent.parent.resolve()
    build_dir = root_dir / ".build" / "coverage"
    if build_dir.exists():
        shutil.rmtree(build_dir)
    build_dir.mkdir(parents=True)
    
    # We must first regenerate workspace/project
    run_command(["xcodegen", "-s", "project.yml"], cwd=root_dir)
    
    # Run tests for all three schemes
    schemes = ["SSBNetwork", "ScuttleRoomApp", "git-remote-ssb"]
    result_paths = []
    
    for scheme in schemes:
        result_path = build_dir / f"{scheme}.xcresult"
        build_and_test(scheme, result_path)
        result_paths.append(result_path)
        
    print("All tests passed. Merging coverage...")
    
    merged_path = build_dir / "merged.xcresult"
    merge_cmd = ["xcrun", "xcresulttool", "merge", "--output-path", str(merged_path)]
    for path in result_paths:
        merge_cmd.append(str(path))
        
    run_command(merge_cmd, cwd=root_dir)
    
    print("Exporting coverage to JSON...")
    report_json_str = run_command(["xcrun", "xccov", "view", "--report", "--json", str(merged_path)])
    report = json.loads(report_json_str)
    
    # Parse report
    # We are looking for files belonging to shipped targets.
    # Coverage Exclusions: Tests, Demos, Linux-only files, generated Plist metadata.
    # By default, xccov groups by target, so we only look at targets: SSBNetwork.framework, ScuttleRoomApp.app, git-remote-ssb
    
    shipped_targets = ["SSBNetwork.framework", "ScuttleRoomApp.app", "git-remote-ssb"]
    
    violation_found = False
    
    for target in report.get('targets', []):
        if target['name'] not in shipped_targets:
            continue
            
        target_name = target['name']
        print(f"Analyzing Target: {target_name} Coverage: {target['lineCoverage'] * 100:.2f}%")
        
        for file in target.get('files', []):
            filename = file['name']
            
            line_cov = file.get('lineCoverage', 0)
            if line_cov < 1.0:
                print(f"❌ {target_name} -> {filename} line coverage: {line_cov * 100:.2f}% (Needs 100%)")
                violation_found = True
                
            for function in file.get('functions', []):
                func_name = function['name']
                # Functions like `__cov_m` shouldn't fail, but usually they don't show up. 
                # Check execution count or coverage
                func_cov = function.get('lineCoverage', 0)
                if func_cov < 1.0:
                    print(f"❌ {target_name} -> {filename} -> function '{func_name}' coverage: {func_cov * 100:.2f}% (Needs 100%)")
                    violation_found = True

    if violation_found:
        print("\nCoverage gate failed! Please ensure 100.00% executable-line and function/block coverage for all shipped targets.")
        sys.exit(1)
    else:
        print("\n✅ 100% Coverage Gate Passed! All shipped code is fully covered.")
        sys.exit(0)

if __name__ == "__main__":
    main()
