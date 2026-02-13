#!/usr/bin/env bash
set -euo pipefail

# Tail training progress lines from latest run logs.
# Defaults to watching latest main + ablation directories.
#
# Examples:
#   ./scripts/watch_progress.sh
#   ./scripts/watch_progress.sh --phase main
#   ./scripts/watch_progress.sh --seed 73
#   ./scripts/watch_progress.sh --raw

PHASE="all"
SEED=""
RAW=0

usage() {
  cat <<'USAGE'
Usage: watch_progress.sh [--phase all|main|ablation] [--seed N] [--raw]

Options:
  --phase      Which logs to watch (default: all)
  --seed       Filter log files by seed suffix (_s<seed>.log)
  --raw        Do not filter lines; stream full logs
  -h, --help   Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      PHASE="${2:-}"
      shift 2
      ;;
    --seed)
      SEED="${2:-}"
      shift 2
      ;;
    --raw)
      RAW=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$PHASE" != "all" && "$PHASE" != "main" && "$PHASE" != "ablation" ]]; then
  echo "Invalid --phase: $PHASE (expected all|main|ablation)" >&2
  exit 1
fi

latest_dir() {
  local pattern="$1"
  local d
  d=$(find run_logs -maxdepth 1 -type d -name "$pattern" -print 2>/dev/null | sort | tail -1 || true)
  printf "%s" "$d"
}

collect_files() {
  local dir="$1"
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    return 0
  fi

  if [[ -n "$SEED" ]]; then
    find "$dir" -maxdepth 1 -type f -name "*_s${SEED}.log" -print | sort
  else
    find "$dir" -maxdepth 1 -type f -name "*.log" -print | sort
  fi
}

main_dir=""
abl_dir=""
if [[ "$PHASE" == "all" || "$PHASE" == "main" ]]; then
  main_dir=$(latest_dir "panda_main_*")
fi
if [[ "$PHASE" == "all" || "$PHASE" == "ablation" ]]; then
  abl_dir=$(latest_dir "panda_shared_only_*")
fi

mapfile -t main_files < <(collect_files "$main_dir")
mapfile -t abl_files < <(collect_files "$abl_dir")

files=()
files+=("${main_files[@]}")
files+=("${abl_files[@]}")

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No log files found to watch."
  echo "Searched latest dirs:"
  echo "  main: ${main_dir:-<none>}"
  echo "  ablation: ${abl_dir:-<none>}"
  echo "If runs are active, check run_logs/ manually."
  exit 1
fi

echo "Watching ${#files[@]} log file(s)..."
for f in "${files[@]}"; do
  echo "  $f"
done

if [[ "$RAW" -eq 1 ]]; then
  tail -n 30 -F "${files[@]}"
else
  if command -v rg >/dev/null 2>&1; then
    tail -n 30 -F "${files[@]}" | rg --line-buffered '^\| train|^\| eval|^\| eval_scenarios|MISSING:'
  else
    tail -n 30 -F "${files[@]}" | grep --line-buffered -E '^\| train|^\| eval|^\| eval_scenarios|MISSING:'
  fi
fi
