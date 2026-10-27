#!/usr/bin/env python3
"""Run the Nest driver in this fork's SmartThings Lua integration tests."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    driver = root / "drivers" / "Personal" / "nest-matter-thermostat"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, default=root / "lua_libs")
    parser.add_argument("--lua", default="lua5.3", help="Lua 5.3 executable")
    parser.add_argument("--filter", default="", help="Regex matching test filenames")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()
    sdk = args.sdk.resolve()
    if not (sdk / "integration_test" / "init.lua").is_file():
        parser.error(f"SmartThings test SDK not found at {sdk}; see README setup")
    lua = shutil.which(args.lua)
    if lua is None:
        parser.error(f"Lua executable not found: {args.lua}")
    version = subprocess.run([lua, "-e", "print(_VERSION)"], capture_output=True, text=True, check=True)
    if version.stdout.strip() != "Lua 5.3":
        parser.error(f"Tests require Lua 5.3, found {version.stdout.strip()}")
    tests = [path for path in sorted((driver / "src" / "test").glob("test_*.lua"))
             if re.search(args.filter, path.name)]
    if not tests:
        parser.error("No test files matched")
    env = os.environ.copy()
    env["LUA_PATH"] = f"{sdk}/?.lua;{sdk}/?/init.lua;./?.lua;./?/init.lua;;"
    failures = []
    total_passed = total_tests = 0
    for path in tests:
        result = subprocess.run([lua, str(path)], cwd=driver / "src", env=env,
                                capture_output=True, text=True)
        summaries = re.findall(r"Passed (\d+) of (\d+) tests", result.stdout)
        passed, count = map(int, summaries[-1]) if summaries else (0, 0)
        success = result.returncode == 0 and bool(summaries) and passed == count
        total_passed += passed
        total_tests += count
        print(f"{'PASS' if success else 'FAIL'} {path.name}: {passed}/{count}", flush=True)
        if args.verbose or not success:
            print(result.stdout, end="")
            print(result.stderr, end="", file=sys.stderr)
        if not success:
            failures.append(path.name)
    print(f"Total: {total_passed}/{total_tests} tests; {len(failures)} failed test files")
    return 1 if failures or total_tests == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
