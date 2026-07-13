#!/usr/bin/env bash
set -euo pipefail

PYTHON_BIN="${PYTHON:-python}"
if [[ -x ".venv/bin/python" ]]; then
  PYTHON_BIN=".venv/bin/python"
elif [[ -x ".venv/Scripts/python.exe" ]]; then
  PYTHON_BIN=".venv/Scripts/python.exe"
fi

"$PYTHON_BIN" scripts/compile_vyper.py
"$PYTHON_BIN" -m ruff check tests scripts
"$PYTHON_BIN" -m pytest -q
