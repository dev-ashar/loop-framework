#!/usr/bin/env bash
# Validate path:line — "snippet" evidence anchors in an explorer report.

set -u

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  printf 'usage: check-anchors.sh <report-file> [repo-root]\n' >&2
  exit 2
fi

report=$1
if [ ! -f "$report" ]; then
  printf 'ANCHOR_FAIL report file missing: %s\n' "$report"
  exit 1
fi

if [ "$#" -eq 2 ]; then
  repo_root=$2
else
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    printf 'ANCHOR_FAIL repository root unavailable\n'
    exit 1
  }
fi

python3 - "$report" "$repo_root" <<'PY'
import os
import re
import sys

report_path = os.path.abspath(sys.argv[1])
repo_root = os.path.realpath(sys.argv[2])

with open(report_path, encoding="utf-8") as handle:
    lines = handle.read().splitlines()

# Each quote style has its own closing delimiter. This keeps an apostrophe
# inside a double-quoted snippet from ending the anchor prematurely.
anchor_re = re.compile(
    r'(?P<path>[^:\n]+):(?P<line>[0-9]+)\s*(?:-|—)\s*'
    r'(?:(?P<double>"[^"\n]*")|'
    r"(?P<single>'[^'\n]*')|"
    r'(?P<curly_double>“[^”\n]*”)|'
    r'(?P<curly_single>‘[^’\n]*’))'
)
snippet_groups = ('double', 'single', 'curly_double', 'curly_single')
anchors = []
faults = []

for number, text in enumerate(lines, 1):
    for match in anchor_re.finditer(text):
        quoted = next(
            match.group(name) for name in snippet_groups
            if match.group(name) is not None
        )
        anchors.append((number, match, quoted[1:-1]))

if not anchors:
    faults.append('ANCHOR_FAIL report contains zero anchors')

for number, text in enumerate(lines, 1):
    if re.search(r'NOT CHECKED', text, re.IGNORECASE):
        continue
    for phrase in ('likely', 'path assumed', 'implicit'):
        if re.search(re.escape(phrase), text, re.IGNORECASE):
            faults.append(
                'ANCHOR_FAIL hedge word %r at report line %d' % (phrase, number)
            )

for report_line, match, raw_snippet in anchors:
    relative_path = match.group('path').strip()
    line_number = int(match.group('line'))
    snippet = raw_snippet.strip()
    if not snippet:
        faults.append(
            'ANCHOR_FAIL empty snippet at report line %d' % report_line
        )
        continue

    target = os.path.realpath(os.path.join(repo_root, relative_path))
    try:
        inside_repo = os.path.commonpath((repo_root, target)) == repo_root
    except ValueError:
        inside_repo = False
    if not inside_repo:
        faults.append(
            'ANCHOR_FAIL path outside repo root %s (report line %d)' %
            (relative_path, report_line)
        )
        continue

    if not os.path.isfile(target):
        faults.append(
            'ANCHOR_FAIL missing file %s (report line %d)' %
            (relative_path, report_line)
        )
        continue

    with open(target, encoding='utf-8') as handle:
        target_lines = handle.read().splitlines()
    if line_number < 1 or line_number > len(target_lines):
        faults.append(
            'ANCHOR_FAIL line out of range %s:%d (report line %d)' %
            (relative_path, line_number, report_line)
        )
        continue

    source_line = target_lines[line_number - 1].strip()
    if snippet not in source_line:
        faults.append(
            'ANCHOR_FAIL wrong snippet %s:%d (report line %d)' %
            (relative_path, line_number, report_line)
        )

for fault in faults:
    print(fault)

if faults:
    raise SystemExit(1)
print('ANCHORS_OK %d' % len(anchors))
PY
