#!/usr/bin/env python3
"""Generate PNG plots from remote result zips/CSVs (Pillow-based, no numpy/matplotlib)."""

from __future__ import annotations

import csv
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
REMOTE = ROOT / "remote_results"
IMAGES = ROOT / "images"
SUMMARY_MD = REMOTE / "analysis_summary.md"

SEED = "73"

RUNS = {
    "single_first": "panda_reach_sac_first_person_repro",
    "single_front": "panda_reach_sac_third_person_front_repro",
    "single_side": "panda_reach_sac_third_person_side_repro",
    "mvd": "panda_reach_sac_mvd_repro",
    "shared_only": "panda_reach_sac_mvd_shared_only_ablation",
}

CAMERA_KEYS = {
    "first": "first_person_cam_success_rate",
    "front": "third_person_front_cam_success_rate",
    "side": "third_person_side_cam_success_rate",
}

COLORS = {
    "single": (31, 119, 180),
    "mvd": (214, 39, 40),
    "shared": (44, 160, 44),
}


@dataclass
class RunSource:
    run_name: str
    eval_csv: Path
    eval_scenarios_csv: Path
    config_log: Path
    max_eval_step: int


@dataclass
class Series:
    label: str
    points: List[Tuple[float, float]]
    color: Tuple[int, int, int]


def ensure_extracted() -> None:
    if not REMOTE.exists():
        raise SystemExit(f"Missing folder: {REMOTE}")

    for pc_dir in sorted(p for p in REMOTE.iterdir() if p.is_dir()):
        extracted = pc_dir / "extracted"
        zips = sorted(pc_dir.glob("*.zip"))

        if not zips:
            continue

        extracted.mkdir(parents=True, exist_ok=True)
        if any(extracted.rglob("*.csv")):
            continue

        for zpath in zips:
            with zipfile.ZipFile(zpath, "r") as zf:
                zf.extractall(extracted)


def read_csv(path: Path) -> Tuple[List[str], List[Dict[str, str]]]:
    rows: List[Dict[str, str]] = []
    with path.open("r", newline="") as f:
        reader = csv.DictReader(f)
        fields = [c.strip().replace("\r", "") for c in (reader.fieldnames or [])]
        for raw in reader:
            cleaned: Dict[str, str] = {}
            for k, v in raw.items():
                if k is None:
                    continue
                ck = k.strip().replace("\r", "")
                cv = (v or "").strip().replace("\r", "")
                cleaned[ck] = cv
            rows.append(cleaned)
    return fields, rows


def to_int(value: str) -> int:
    return int(float(value)) if value else 0


def to_float(value: str) -> float:
    return float(value) if value else 0.0


def choose_best_source(run_name: str) -> RunSource:
    candidates: List[RunSource] = []

    for extracted in sorted(REMOTE.glob("*/extracted")):
        for eval_csv in extracted.rglob(f"*/{run_name}/{SEED}/eval.csv"):
            eval_scen = eval_csv.with_name("eval_scenarios.csv")
            config_log = eval_csv.with_name("config.log")
            if not eval_scen.exists() or not config_log.exists():
                continue

            _, rows = read_csv(eval_csv)
            if not rows:
                continue
            max_step = max(to_int(r.get("step", "0")) for r in rows)

            candidates.append(
                RunSource(
                    run_name=run_name,
                    eval_csv=eval_csv,
                    eval_scenarios_csv=eval_scen,
                    config_log=config_log,
                    max_eval_step=max_step,
                )
            )

    if not candidates:
        raise RuntimeError(f"No candidates found for run: {run_name}")

    candidates.sort(key=lambda c: (c.max_eval_step, str(c.eval_csv)))
    return candidates[-1]


def read_eval_success(path: Path) -> List[Tuple[int, float]]:
    _, rows = read_csv(path)
    pts = []
    for r in rows:
        if "step" in r and "success_rate" in r:
            pts.append((to_int(r["step"]), to_float(r["success_rate"])))
    pts.sort(key=lambda x: x[0])
    return pts


def read_eval_scenario_success(path: Path) -> Dict[str, List[Tuple[int, float]]]:
    fields, rows = read_csv(path)
    if not rows:
        return {k: [] for k in CAMERA_KEYS.values()}
    if "step" not in fields:
        raise RuntimeError(f"Missing step in {path}")

    out: Dict[str, List[Tuple[int, float]]] = {k: [] for k in CAMERA_KEYS.values()}

    for r in rows:
        step = to_int(r.get("step", "0"))
        for key in out:
            if key in r and r[key] != "":
                out[key].append((step, to_float(r[key])))

    for key in out:
        out[key].sort(key=lambda x: x[0])

    return out


def clip_points(points: Sequence[Tuple[int, float]], max_step: int) -> List[Tuple[float, float]]:
    return [(float(s), float(v)) for s, v in points if s <= max_step]


def final_value(points: Sequence[Tuple[int, float]]) -> Tuple[int, float]:
    if not points:
        return (0, float("nan"))
    return points[-1]


def step_label(x: int) -> str:
    if x >= 1000:
        return f"{int(x/1000)}k"
    return str(x)


def load_font(size: int) -> ImageFont.ImageFont:
    for name in ("DejaVuSans.ttf", "Arial.ttf", "LiberationSans-Regular.ttf"):
        try:
            return ImageFont.truetype(name, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def draw_line_plot_png(
    path: Path,
    title: str,
    subtitle: str,
    series: Sequence[Series],
    x_max: int,
) -> None:
    width, height = 1000, 1000
    ml, mr, mt, mb = 110, 60, 120, 120
    pw, ph = width - ml - mr, height - mt - mb

    img = Image.new("RGB", (width, height), "white")
    d = ImageDraw.Draw(img)

    font_title = load_font(40)
    font_subtitle = load_font(22)
    font_tick = load_font(17)
    font_axis = load_font(24)
    font_legend = load_font(18)
    font_value = load_font(16)

    def sx(x: float) -> float:
        return ml + (x / x_max) * pw

    def sy(y: float) -> float:
        return mt + (1.0 - y) * ph

    d.text((ml, 16), title, fill=(15, 15, 15), font=font_title)
    d.text((ml, 64), subtitle, fill=(70, 70, 70), font=font_subtitle)

    for i in range(6):
        yv = i * 0.2
        y = sy(yv)
        color = (210, 210, 210) if i > 0 else (150, 150, 150)
        d.line((ml, y, ml + pw, y), fill=color, width=1)
        d.text((ml - 46, y - 8), f"{yv:.1f}", fill=(50, 50, 50), font=font_tick)

    tick_step = 50000 if x_max > 170000 else 20000
    ticks = list(range(0, x_max + 1, tick_step))
    if ticks[-1] != x_max:
        ticks.append(x_max)

    for xv in ticks:
        x = sx(float(xv))
        d.line((x, mt, x, mt + ph), fill=(235, 235, 235), width=1)
        d.text((x - 18, mt + ph + 22), step_label(xv), fill=(50, 50, 50), font=font_tick)

    d.line((ml, mt, ml, mt + ph), fill=(60, 60, 60), width=2)
    d.line((ml, mt + ph, ml + pw, mt + ph), fill=(60, 60, 60), width=2)

    d.text((ml + pw // 2 - 95, height - 55), "Environment steps", fill=(20, 20, 20), font=font_axis)
    d.text((20, mt + ph // 2 - 10), "Success rate", fill=(20, 20, 20), font=font_axis)

    legend_x = ml + 12
    legend_y = mt + 12
    for i, s in enumerate(series):
        pts = [(x, y) for x, y in s.points if x <= x_max]
        if len(pts) >= 2:
            pix = [(sx(x), sy(y)) for x, y in pts]
            d.line(pix, fill=s.color, width=4, joint="curve")
            fx, fy = pix[-1]
            d.ellipse((fx - 4, fy - 4, fx + 4, fy + 4), fill=s.color)
            d.text((fx + 10, fy - 12), f"{pts[-1][1]:.2f}", fill=s.color, font=font_value)

        ly = legend_y + i * 24
        d.line((legend_x, ly + 6, legend_x + 22, ly + 6), fill=s.color, width=4)
        d.text((legend_x + 30, ly - 3), s.label, fill=(20, 20, 20), font=font_legend)

    img.save(path, "PNG")


def main() -> None:
    ensure_extracted()
    IMAGES.mkdir(parents=True, exist_ok=True)

    for p in IMAGES.glob("*.svg"):
        p.unlink()
    for stale in [
        IMAGES / "all_cameras_mvd_vs_shared_only.png",
        IMAGES / "all_cameras_mvd_vs_shared_only_common_horizon.png",
        IMAGES / "ablation_per_camera_mvd_vs_shared_only.png",
    ]:
        if stale.exists():
            stale.unlink()

    selected: Dict[str, RunSource] = {k: choose_best_source(v) for k, v in RUNS.items()}

    eval_data = {k: read_eval_success(v.eval_csv) for k, v in selected.items()}
    scenario_data = {k: read_eval_scenario_success(v.eval_scenarios_csv) for k, v in selected.items()}

    shared_all_max = final_value(eval_data["shared_only"])[0]
    draw_line_plot_png(
        IMAGES / "all_cameras_mvd_vs_shared_only.png",
        "Panda Reach: All-Camera Success",
        f"MVD vs SharedOnly (clipped to {shared_all_max} steps)",
        [
            Series("MVD", clip_points(eval_data["mvd"], shared_all_max), COLORS["mvd"]),
            Series("SharedOnly", clip_points(eval_data["shared_only"], shared_all_max), COLORS["shared"]),
        ],
        x_max=shared_all_max,
    )

    cam_defs = [
        ("first", "First-Person", "single_first", "camera_first_single_vs_mvd.png"),
        ("front", "Third-Person Front", "single_front", "camera_front_single_vs_mvd.png"),
        ("side", "Third-Person Side", "single_side", "camera_side_single_vs_mvd.png"),
    ]

    for cam_id, cam_title, single_key, out_name in cam_defs:
        ckey = CAMERA_KEYS[cam_id]
        mvd_xmax = final_value(scenario_data["mvd"][ckey])[0]
        single_xmax = final_value(scenario_data[single_key][ckey])[0]
        xmax = max(mvd_xmax, single_xmax)
        draw_line_plot_png(
            IMAGES / out_name,
            f"Panda Reach: {cam_title} Success",
            "Single-camera SAC vs MVD per-camera eval",
            [
                Series("Single-camera SAC", [(float(x), y) for x, y in scenario_data[single_key][ckey]], COLORS["single"]),
                Series("MVD", [(float(x), y) for x, y in scenario_data["mvd"][ckey]], COLORS["mvd"]),
            ],
            x_max=xmax,
        )

    for cam_id, cam_title, out_name in [
        ("first", "First-Person", "ablation_first_mvd_vs_shared_only.png"),
        ("front", "Third-Person Front", "ablation_front_mvd_vs_shared_only.png"),
        ("side", "Third-Person Side", "ablation_side_mvd_vs_shared_only.png"),
    ]:
        ckey = CAMERA_KEYS[cam_id]
        shared_xmax = final_value(scenario_data["shared_only"][ckey])[0]
        draw_line_plot_png(
            IMAGES / out_name,
            f"Ablation: {cam_title} Success",
            f"MVD vs SharedOnly (clipped to {shared_xmax} steps)",
            [
                Series("MVD", clip_points(scenario_data["mvd"][ckey], shared_xmax), COLORS["mvd"]),
                Series("SharedOnly", clip_points(scenario_data["shared_only"][ckey], shared_xmax), COLORS["shared"]),
            ],
            x_max=shared_xmax,
        )

    lines: List[str] = []
    lines.append("# Remote Results Summary")
    lines.append("")
    lines.append(f"Data root: `{REMOTE}`")
    lines.append("")
    lines.append("## Selected CSV sources")
    lines.append("")
    lines.append("| Run | Source eval.csv | Max eval step |")
    lines.append("|---|---|---:|")
    for key in ["single_first", "single_front", "single_side", "mvd", "shared_only"]:
        src = selected[key]
        lines.append(f"| {src.run_name} | `{src.eval_csv}` | {src.max_eval_step} |")

    lines.append("")
    lines.append("## Generated images")
    lines.append("")
    for p in sorted(IMAGES.glob("*.png")):
        lines.append(f"- `{p.relative_to(ROOT)}`")

    SUMMARY_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Wrote summary: {SUMMARY_MD}")
    for p in sorted(IMAGES.glob("*.png")):
        print(f"Wrote image: {p}")


if __name__ == "__main__":
    main()
