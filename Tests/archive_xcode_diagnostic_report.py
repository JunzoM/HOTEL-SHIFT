#!/usr/bin/env python3
"""Archive a build report without overwriting earlier runs; maintain a bounded index."""
import argparse
import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def archive(source: Path, directory: Path, *, stamp=None):
    data = json.loads(source.read_text(encoding='utf-8'))
    if not isinstance(data, dict) or data.get('schema_version') != 1 or data.get('result') not in ('success', 'failure'):
        raise ValueError('invalid diagnostic report')
    directory.mkdir(parents=True, exist_ok=True)
    stamp = stamp or datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    if not re.fullmatch(r'[0-9]{8}T[0-9]{12}Z', stamp):
        raise ValueError('invalid timestamp')
    target = directory / f'build-{stamp}.json'
    # Exclusive creation protects previous history from being overwritten.
    with target.open('x', encoding='utf-8') as output:
        json.dump(data, output, ensure_ascii=False, indent=2)
        output.write('\n')
    index = directory / 'index.json'
    records = []
    for path in sorted(directory.glob('build-*.json')):
        try:
            entry = json.loads(path.read_text(encoding='utf-8'))
            if entry.get('schema_version') == 1 and entry.get('result') in ('success', 'failure'):
                records.append({'file': path.name, 'result': entry['result'], 'diagnostic_count': entry.get('diagnostic_count', 0)})
        except (ValueError, OSError, AttributeError):
            continue
    fd, temporary = tempfile.mkstemp(prefix='.history-', suffix='.json', dir=directory)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as out:
            json.dump({'schema_version': 1, 'builds': records}, out, ensure_ascii=False, indent=2)
            out.write('\n')
        os.replace(temporary, index)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--directory', type=Path, default=Path('reports/history'))
    args = parser.parse_args()
    try:
        print(f'Archived report: {archive(args.report, args.directory)}')
    except (OSError, ValueError, TypeError) as exc:
        parser.exit(2, f'Cannot archive report: {exc}\n')


if __name__ == '__main__':
    main()
