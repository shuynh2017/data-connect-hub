#!/usr/bin/env bash
# e2e/run-e2e.sh — One-stop E2E test runner for Data Connect Hub.
#
# Reads configuration from a file, prepares K8s resources, installs
# dependencies, and runs pytest.
#
# Usage:
#   ./e2e/run-e2e.sh e2e/env.local
#   make e2e-test ENV=e2e/env.local

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the config file (only export known variables)
set -a
# shellcheck source=/dev/null
source "$SCRIPT_DIR/dch.env"
set +a

# ===================================================================
# Main
# ===================================================================

echo "=== E2E Setup ==="

# 1. Install dependencies
VENV_DIR="$SCRIPT_DIR/.venv"
if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi
VENV_PYTHON="$VENV_DIR/bin/python3"
VENV_PYTEST="$VENV_DIR/bin/pytest"
if [[ ! -x "$VENV_PYTEST" ]]; then
    "$VENV_PYTHON" -m pip install --quiet \
        -e "$REPO_ROOT/sdk/python[flight]" \
        -e "$SCRIPT_DIR"
fi
echo "[1/11] Dependencies ready"

# -------------------------------------------------------------------
# Run tests
# -------------------------------------------------------------------

echo ""
echo "=== Running E2E Tests ==="
cd "$SCRIPT_DIR"
exec "$VENV_PYTEST" tests/ -v "$@"
