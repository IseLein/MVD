# Panda Reproduction + Shared-Only Ablation Runbook

This runbook executes:

1. Main reproduction on `main`:
- `SAC-MVD` (multi-camera)
- `SAC` single-camera baselines for:
  - `first_person`
  - `third_person_front`
  - `third_person_side`

2. Shared-only ablation on `abl/shared_only`:
- `SAC-MVD-SharedOnly`

All runs use 5 seeds (`0..4`) and produce CSVs under run directories.

## 1. Environment Setup

```bash
conda env create -f conda_env.yml
conda activate multi_view_disentanglement
```

For headless SSH machines, prefer virtual display (recommended):

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y xvfb
```

The script uses `xvfb-run` by default.

Run preflight before long jobs:

```bash
bash scripts/preflight_remote.sh
```

## 2. Branch Setup

Make sure both branches exist locally:

```bash
git switch main
git pull --ff-only
git branch --list abl/shared_only
```

If `abl/shared_only` is missing, create it from the shared-only commit before running.

## 3. Parallelization Defaults

Given `A100 80GB`, `31 vCPU`, `117GB RAM`, the default is:
- `MAX_JOBS=4`

This is parallel execution with background jobs (`&`) + a concurrency cap (`wait -n`).

## 4. Run Everything

Use the single script:

```bash
MAX_JOBS=4 GPU_ID=0 USE_XVFB=1 ./scripts/run_panda_repro_and_shared_only.sh
```

Optional knobs:
- `SEEDS="0 1 2 3 4"`
- `MAIN_OUT_DIR=runs_repro`
- `ABL_OUT_DIR=runs_ablation`
- `MAIN_LOG_DIR=run_logs/panda_main_custom`
- `ABL_LOG_DIR=run_logs/panda_shared_only_custom`

Example:

```bash
MAX_JOBS=4 \
GPU_ID=0 \
USE_XVFB=1 \
SEEDS="0 1 2 3 4" \
MAIN_OUT_DIR=runs_repro \
ABL_OUT_DIR=runs_ablation \
./scripts/run_panda_repro_and_shared_only.sh
```

## 5. What the Script Does

- Verifies clean tracked git state before branch switching.
- Runs on `main`:
  - 15 single-camera jobs total (3 cameras x 5 seeds)
  - then 5 MVD jobs
- Switches to `abl/shared_only` and runs 5 shared-only jobs.
- Writes commit hashes used for each phase to:
  - `run_meta/main_commit_for_repro.txt`
  - `run_meta/abl_shared_only_commit.txt`
- Checks expected CSV files for every run.

Live monitoring helper:

```bash
# watch latest main + ablation logs
./scripts/watch_progress.sh

# watch only main logs for seed 73
./scripts/watch_progress.sh --phase main --seed 73
```

## 6. Expected Output Locations

Main reproduction CSVs:
- `runs_repro/panda_reach_sac_first_person_repro/<seed>/eval.csv`
- `runs_repro/panda_reach_sac_first_person_repro/<seed>/eval_scenarios.csv`
- `runs_repro/panda_reach_sac_third_person_front_repro/<seed>/eval.csv`
- `runs_repro/panda_reach_sac_third_person_front_repro/<seed>/eval_scenarios.csv`
- `runs_repro/panda_reach_sac_third_person_side_repro/<seed>/eval.csv`
- `runs_repro/panda_reach_sac_third_person_side_repro/<seed>/eval_scenarios.csv`
- `runs_repro/panda_reach_sac_mvd_repro/<seed>/eval.csv`
- `runs_repro/panda_reach_sac_mvd_repro/<seed>/eval_scenarios.csv`

Shared-only ablation CSVs:
- `runs_ablation/panda_reach_sac_mvd_shared_only_ablation/<seed>/eval.csv`
- `runs_ablation/panda_reach_sac_mvd_shared_only_ablation/<seed>/eval_scenarios.csv`

## 7. Notes

- Run directories must not already exist for the same `exp_name/seed` pair (`train.py` asserts this).
- CSV files are not tracked by git by default.
- If you already have X forwarding and want to disable virtual display:

```bash
USE_XVFB=0 ./scripts/run_panda_repro_and_shared_only.sh
```
