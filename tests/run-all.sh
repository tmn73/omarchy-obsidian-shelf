#!/usr/bin/env bash
# Every automated check of the plugin, in one command.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
PYTHONPATH=helper python3 -m unittest discover -s tests
node --test tests/model.test.js tests/board.test.js
bash tests/qml-source-test.sh
bash tests/setup-scripts-test.sh
omarchy plugin validate "$ROOT"
echo "all checks passed"
