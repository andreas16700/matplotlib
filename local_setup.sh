#!/usr/bin/env bash
set -euo pipefail

# --- Configuration -----------------------------------------------------------
PYVER="3.13.7"
VENV_DIR=".venv"

# --- Helpers -----------------------------------------------------------------
abort() { echo "❌ $*" >&2; exit 1; }
info()  { echo "➤ $*"; }

require_file() {
  [[ -f "$1" ]] || abort "Missing required file: $1 (run this from the repo root)."
}

# --- Preflight checks --------------------------------------------------------
require_file "pyproject.toml"
require_file "requirements/testing/all.txt"
require_file "requirements/testing/minver.txt"

if ! command -v pyenv >/dev/null 2>&1; then
  info "pyenv not found. Attempting to install via Homebrew (macOS)…"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    command -v brew >/dev/null 2>&1 || abort "Homebrew not found. Install from https://brew.sh and re-run."
    brew update
    brew install pyenv
    # Useful build deps for CPython via pyenv on macOS
    brew install openssl readline xz zlib || true
  else
    abort "pyenv is required. Install pyenv for your OS and re-run."
  fi
fi

# --- Install and select Python ----------------------------------------------
info "Ensuring Python ${PYVER} is installed with pyenv…"
# -s: skip if already installed
CFLAGS="-O3" pyenv install -s "${PYVER}"

info "Setting local Python to ${PYVER}…"
pyenv local "${PYVER}"

# Make sure the shims are active in this shell (common on macOS)
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi

info "Using Python: $(python -V)"
command -v python || abort "python not on PATH after pyenv setup."

# --- Fresh virtual environment ----------------------------------------------
if [[ -d "${VENV_DIR}" ]]; then
  info "Removing existing virtualenv ${VENV_DIR}…"
  rm -rf "${VENV_DIR}"
fi

info "Creating virtualenv ${VENV_DIR}…"
python -m venv "${VENV_DIR}"
# shellcheck disable=SC1090
source "${VENV_DIR}/bin/activate"

info "Upgrading pip/setuptools/wheel…"
python -m pip install -U pip wheel setuptools

# Optional: match CI environment niceties
export OPENBLAS_NUM_THREADS=1
export PYTHONFAULTHANDLER=1
export NO_AT_BRIDGE=1

# --- Dependency installation (mirrors your CI) -------------------------------
info "Installing core build + runtime deps…"
python -m pip install --upgrade \
  'contourpy>=1.0.1' cycler fonttools kiwisolver packaging pillow \
  'pyparsing!=3.1.0' python-dateutil setuptools-scm \
  'meson-python>=0.13.1' 'pybind11>=2.13.2'

info "Installing full test requirements…"
python -m pip install -r requirements/testing/all.txt

info "Installing test runner…"
python -m pip install pytest

info "Installing optional Sphinx (harmless if present)…"
python -m pip install 'sphinx!=6.1.2'

# --- Install your project (editable, Agg backend) ----------------------------
info "Installing project in editable mode with Agg backend (no deps, no build isolation)…"
python -m pip install --no-deps --no-build-isolation --verbose \
  --config-settings=setup-args="-DrcParams-backend=Agg" \
  --editable .[dev]

info "✅ Done."
echo
echo "Python:    $(python -V)"
echo "Which pip: $(command -v pip)"
echo "Venv:      ${VENV_DIR}"
