#!/usr/bin/env bash
set -euo pipefail

# Preflight checks for running Panda/MVD training on a remote/headless machine.
# Usage:
#   conda activate multi_view_disentanglement
#   bash scripts/preflight_remote.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FAILED=0

ok() { echo "[OK]  $*"; }
warn() { echo "[WARN] $*"; }
err() { echo "[ERR] $*"; FAILED=1; }

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "command found: $cmd"
  else
    err "missing command: $cmd"
  fi
}

echo "== System checks =="
check_cmd gcc
check_cmd g++
check_cmd make
check_cmd python3
check_cmd xvfb-run

if command -v nvidia-smi >/dev/null 2>&1; then
  ok "nvidia-smi available"
  nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || true
else
  warn "nvidia-smi not found (GPU may be unavailable in this session)"
fi

echo

echo "== Header/library checks =="
if [[ -f /usr/include/GL/osmesa.h ]] || [[ -f /usr/local/include/GL/osmesa.h ]]; then
  ok "osmesa header found (GL/osmesa.h)"
else
  err "GL/osmesa.h not found"
  echo "      Install (Ubuntu/Debian):"
  echo "      apt-get update && apt-get install -y libosmesa6-dev libgl1-mesa-dev libglfw3 libglew-dev build-essential patchelf xvfb"
fi

if ldconfig -p 2>/dev/null | grep -Eq "libOSMesa|libEGL|libGL"; then
  ok "OpenGL/EGL libraries detected via ldconfig"
else
  warn "Could not confirm OpenGL/EGL libs with ldconfig"
fi

echo

echo "== Python package checks =="
if python3 - <<'PY'
import importlib
mods = [
    "torch",
    "gymnasium",
    "panda_gym",
    "pybullet",
    "cv2",
    "kornia",
]
failed = []
for m in mods:
    try:
        importlib.import_module(m)
        print(f"[OK]  import {m}")
    except Exception as e:
        print(f"[ERR] import {m}: {e}")
        failed.append(m)

if failed:
    raise SystemExit(1)
PY
then
  ok "core Python imports passed"
else
  err "core Python import checks failed"
fi

echo

echo "== mujoco_py build/import check =="
# This intentionally triggers the exact path that failed in your traceback.
if python3 - <<'PY'
import mujoco_py
print("[OK]  import mujoco_py")
PY
then
  ok "mujoco_py import passed"
else
  err "mujoco_py import failed (likely missing system GL/Mesa deps)"
fi

echo

echo "== Panda env smoke test =="
if python3 - <<'PY'
import gymnasium as gym
import panda_gym

env = gym.make("PandaReachDense-v3")
obs, info = env.reset(seed=0)
for _ in range(3):
    a = env.action_space.sample()
    obs, reward, terminated, truncated, info = env.step(a)
    if terminated or truncated:
        obs, info = env.reset(seed=0)
env.close()
print("[OK]  PandaReachDense-v3 reset/step smoke test")
PY
then
  ok "Panda env smoke test passed"
else
  err "Panda env smoke test failed"
fi

echo

echo "== Environment notes =="
if [[ -z "${CONDA_DEFAULT_ENV:-}" ]]; then
  warn "No active conda env detected"
else
  ok "Active conda env: ${CONDA_DEFAULT_ENV}"
fi

if [[ -z "${MUJOCO_GL:-}" ]]; then
  warn "MUJOCO_GL is unset. For headless GPU nodes, set: export MUJOCO_GL=egl"
else
  ok "MUJOCO_GL=${MUJOCO_GL}"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "Preflight PASSED"
  exit 0
else
  echo "Preflight FAILED"
  exit 1
fi
