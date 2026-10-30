#!/usr/bin/env python3
"""Bounded Swift parser smoke test; not an iOS SDK build."""
import argparse
import subprocess
import shutil
import sys
from pathlib import Path


def run(root: Path, swiftc: str, seconds: float):
    sources = sorted(root.rglob('*.swift'))
    if not sources:
        raise ValueError('No Swift sources found')
    failures = []
    for source in sources:
        try:
            result = subprocess.run([swiftc, '-frontend', '-parse', str(source)],
                                    capture_output=True, text=True, timeout=seconds)
        except subprocess.TimeoutExpired:
            failures.append((source, f'timed out after {seconds:g}s'))
            continue
        except OSError as exc:
            failures.append((source, str(exc)))
            break
        if result.returncode:
            failures.append((source, (result.stderr or result.stdout).strip()[:1500]))
    return len(sources), failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT')
    parser.add_argument('--swiftc', default='swiftc')
    parser.add_argument('--timeout', type=float, default=15)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    if shutil.which(args.swiftc) is None:
        print(f'UNAVAILABLE: {args.swiftc} not found; no Swift files checked.', file=sys.stderr)
        return 2
    try:
        total, failures = run(args.root, args.swiftc, args.timeout)
    except ValueError as exc:
        parser.error(str(exc))
    for path, message in failures:
        print(f'FAIL {path}: {message}', file=sys.stderr)
    print(f'Swift parse: {total - len(failures)}/{total} passed (syntax only; no iOS build)')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
