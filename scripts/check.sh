#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest scripts/test_release_integrity.py
swift test
swift test --scratch-path .build/baseline -Xswiftc -DBASELINE
for edition in $(python3 scripts/release_integrity.py list-editions "$PWD"); do
  ./scripts/build-app.sh "$edition"
done
python3 ./scripts/release-info.py
