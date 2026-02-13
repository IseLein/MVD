#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MAX_JOBS="${MAX_JOBS:-4}"
SEEDS="${SEEDS:-0 1 2 3 4}"
GPU_ID="${GPU_ID:-0}"
USE_XVFB="${USE_XVFB:-1}"
XVFB_ARGS="${XVFB_ARGS:--screen 0 1024x768x24}"
MAIN_LOG_DIR="${MAIN_LOG_DIR:-run_logs/panda_main_$(date +%Y%m%d_%H%M%S)}"
ABL_LOG_DIR="${ABL_LOG_DIR:-run_logs/panda_shared_only_$(date +%Y%m%d_%H%M%S)}"
MAIN_OUT_DIR="${MAIN_OUT_DIR:-runs_repro}"
ABL_OUT_DIR="${ABL_OUT_DIR:-runs_ablation}"

export CUDA_VISIBLE_DEVICES="$GPU_ID"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"

ORIG_BRANCH="$(git branch --show-current)"

cleanup() {
  git switch "$ORIG_BRANCH" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: tracked git changes detected. Commit/stash before running this script." >&2
  exit 1
fi

if ! git rev-parse --verify abl/shared_only >/dev/null 2>&1; then
  echo "ERROR: branch 'abl/shared_only' not found. Create it first." >&2
  exit 1
fi

run_job() {
  local log_file="$1"
  shift

  echo "[start] $*"
  if [[ "$USE_XVFB" == "1" ]]; then
    xvfb-run -a -s "$XVFB_ARGS" "$@" >"$log_file" 2>&1 &
  else
    "$@" >"$log_file" 2>&1 &
  fi

  while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
    wait -n
  done
}

wait_for_jobs() {
  wait
}

check_csv() {
  local out_dir="$1"
  local exp_name="$2"

  for seed in $SEEDS; do
    local eval_csv="$out_dir/$exp_name/$seed/eval.csv"
    local scenarios_csv="$out_dir/$exp_name/$seed/eval_scenarios.csv"

    if [[ ! -f "$eval_csv" ]]; then
      echo "MISSING: $eval_csv"
    fi

    if [[ ! -f "$scenarios_csv" ]]; then
      echo "MISSING: $scenarios_csv"
    fi
  done
}

mkdir -p "$MAIN_LOG_DIR" "$ABL_LOG_DIR" run_meta

echo "[phase] Main reproduction runs on branch main"
git switch main >/dev/null
MAIN_COMMIT="$(git rev-parse HEAD)"
printf "%s\n" "$MAIN_COMMIT" > run_meta/main_commit_for_repro.txt

# Phase 1: single-camera baselines
for seed in $SEEDS; do
  run_job "$MAIN_LOG_DIR/panda_reach_sac_first_person_repro_s${seed}.log" \
    python3 train.py \
    --algorithm sac \
    --seed "$seed" \
    --domain_name Panda \
    --task_name PandaReachDense-v3 \
    --exp_name panda_reach_sac_first_person_repro \
    --log_dir "$MAIN_OUT_DIR" \
    --image_reconstruction_loss True \
    --num_train_steps 250000 \
    --eval_freq 5000 \
    --save_freq 250000 \
    --num_eval_episodes 20 \
    --action_repeat 1 \
    --cameras first_person \
    --frame_stack 1 \
    --feature_dim 100
done

for seed in $SEEDS; do
  run_job "$MAIN_LOG_DIR/panda_reach_sac_third_person_front_repro_s${seed}.log" \
    python3 train.py \
    --algorithm sac \
    --seed "$seed" \
    --domain_name Panda \
    --task_name PandaReachDense-v3 \
    --exp_name panda_reach_sac_third_person_front_repro \
    --log_dir "$MAIN_OUT_DIR" \
    --image_reconstruction_loss True \
    --num_train_steps 250000 \
    --eval_freq 5000 \
    --save_freq 250000 \
    --num_eval_episodes 20 \
    --action_repeat 1 \
    --cameras third_person_front \
    --frame_stack 1 \
    --feature_dim 100
done

for seed in $SEEDS; do
  run_job "$MAIN_LOG_DIR/panda_reach_sac_third_person_side_repro_s${seed}.log" \
    python3 train.py \
    --algorithm sac \
    --seed "$seed" \
    --domain_name Panda \
    --task_name PandaReachDense-v3 \
    --exp_name panda_reach_sac_third_person_side_repro \
    --log_dir "$MAIN_OUT_DIR" \
    --image_reconstruction_loss True \
    --num_train_steps 250000 \
    --eval_freq 5000 \
    --save_freq 250000 \
    --num_eval_episodes 20 \
    --action_repeat 1 \
    --cameras third_person_side \
    --frame_stack 1 \
    --feature_dim 100
done
wait_for_jobs

# Phase 2: MVD
for seed in $SEEDS; do
  run_job "$MAIN_LOG_DIR/panda_reach_sac_mvd_repro_s${seed}.log" \
    python3 train.py \
    --algorithm sac \
    --seed "$seed" \
    --domain_name Panda \
    --task_name PandaReachDense-v3 \
    --exp_name panda_reach_sac_mvd_repro \
    --log_dir "$MAIN_OUT_DIR" \
    --image_reconstruction_loss True \
    --num_train_steps 250000 \
    --eval_freq 5000 \
    --save_freq 250000 \
    --num_eval_episodes 20 \
    --action_repeat 1 \
    --cameras first_person third_person_front third_person_side \
    --frame_stack 1 \
    --feature_dim 50 \
    --eval_on_each_camera True \
    --multi_view_disentanglement True
done
wait_for_jobs

echo "[phase] Shared-only ablation on branch abl/shared_only"
git switch abl/shared_only >/dev/null
ABL_COMMIT="$(git rev-parse HEAD)"
printf "%s\n" "$ABL_COMMIT" > run_meta/abl_shared_only_commit.txt

for seed in $SEEDS; do
  run_job "$ABL_LOG_DIR/panda_reach_sac_mvd_shared_only_ablation_s${seed}.log" \
    python3 train.py \
    --algorithm sac \
    --seed "$seed" \
    --domain_name Panda \
    --task_name PandaReachDense-v3 \
    --exp_name panda_reach_sac_mvd_shared_only_ablation \
    --log_dir "$ABL_OUT_DIR" \
    --image_reconstruction_loss True \
    --num_train_steps 250000 \
    --eval_freq 5000 \
    --save_freq 250000 \
    --num_eval_episodes 20 \
    --action_repeat 1 \
    --cameras first_person third_person_front third_person_side \
    --frame_stack 1 \
    --feature_dim 50 \
    --eval_on_each_camera True \
    --multi_view_disentanglement True \
    --mvd_shared_only True
done
wait_for_jobs

echo "[check] verifying expected CSV files"
check_csv "$MAIN_OUT_DIR" "panda_reach_sac_first_person_repro"
check_csv "$MAIN_OUT_DIR" "panda_reach_sac_third_person_front_repro"
check_csv "$MAIN_OUT_DIR" "panda_reach_sac_third_person_side_repro"
check_csv "$MAIN_OUT_DIR" "panda_reach_sac_mvd_repro"
check_csv "$ABL_OUT_DIR" "panda_reach_sac_mvd_shared_only_ablation"

echo "[done] Main logs: $MAIN_LOG_DIR"
echo "[done] Ablation logs: $ABL_LOG_DIR"
echo "[done] Main outputs: $MAIN_OUT_DIR"
echo "[done] Ablation outputs: $ABL_OUT_DIR"
