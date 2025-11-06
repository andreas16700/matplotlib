#!/usr/bin/env bash
set -euo pipefail


source .venv/bin/activate
cd ../pytest-testmon/
echo "installing fork.."
pip install -e . --config-settings editable_mode=compat
echo "done"
