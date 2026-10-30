#!/usr/bin/env python3
"""Run relevant regression tests; report unavailable tools explicitly."""
import subprocess, sys, pathlib, shutil
root=pathlib.Path(__file__).resolve().parents[1]
for name in ("verify_fixed449.py","verify_fixed450.py","verify_fixed451.py"):
    result=subprocess.run([sys.executable,str(root/"Tests"/name)],cwd=root)
    if result.returncode: sys.exit(result.returncode)
print("FIXED451 regression checks PASS")
print("Xcode/macOS build: NOT RUN (requires macOS + Xcode)")
