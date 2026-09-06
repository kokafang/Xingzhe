#!/usr/bin/env python3
"""Exercise the launchd-style relative argv[0] from an unrelated working directory."""
from pathlib import Path
import subprocess
helper = Path(__file__).resolve().parent.parent / "build/醒着.app/Contents/Library/HelperTools/AwakeHelper"
result = subprocess.run(["Contents/Library/HelperTools/AwakeHelper", "--diagnostics"], executable=str(helper), cwd="/", capture_output=True, text=True, check=True)
assert "clientRequirement=" in result.stdout, result.stdout
print("PASS: relative launchd argv[0] resolves signed containing application")
