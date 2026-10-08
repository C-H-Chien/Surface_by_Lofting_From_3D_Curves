#!/usr/bin/env python3
"""Color GT 3D curves and the 2D edge points associated with them.

Each CAD curve gets one color.  The same color is used for that curve in
the 3D figure and for its matched edge points on every image.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image

_THIS = Path(__file__).resolve()


def _load_construction():
    import importlib.util
    path = _THIS.parent / "GT_edge_corresp_construction.py"
    spec = importlib.util.spec_from_file_location("gt_edge_corresp_construction", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_gt = _load_construction()
DEFAULT_DATASET_ROOT = _gt.DEFAULT_DATASET_ROOT
curve_ids_from_gaps = _gt.curve_ids_from_gaps
maybe_flip_z = _gt.maybe_flip_z
sample_gt_curves_from_cad = _gt.sample_gt_curves_from_cad

DEFAULT_ASSOC = _THIS.parent / "GT_edge_corresp_ABC_NEF" / "GT_3D_2D_assoc_0006.json"


def curve_colors(n_curves: int) -> np.ndarray:
    """Distinct RGB colors, one per curve.  Neighbors are far apart in hue."""
    n_curves = max(int(n_curves), 1)
    hues = (np.arange(n_curves, dtype=float) * 0.61803398875) % 1.0
    hsv = np.column_stack([
        hues,
        np.full(n_curves, 0.85),
        np.full(n_curves, 0.95),
    ])
    return matplotlib.colors.hsv_to_rgb(hsv)


def load_association(path: Path) -> dict:
    with open(path) as f:
        payload = json.load(f)
    payload["points"] = np.asarray(payload["points"], dtype=float).reshape(-1, 3)
    if "curve_id" in payload:
        payload["curve_id"] = np.asarray(payload["curve_id"], dtype=int).reshape(-1)
    return payload


def resolve_curve_ids(payload: dict, dataset_root: Path) -> np.ndarray:
    """Curve index of each 3D sample.  Prefer the id stored with the association."""
    points = payload["points"]
    if "curve_id" in payload and payload["curve_id"].shape[0] == points.shape[0]:
        return payload["curve_id"]

    object_id = str(payload["object_id"])
    meta = payload.get("gt_meta") or {}
    try:
        sampled, _, curve_ids, _ = sample_gt_curves_from_cad(
            dataset_root,
            object_id,
            sharp_only=bool(meta.get("sharp_only", True)),
            sample_spacing=float(meta.get("sample_spacing", 0.01)),
        )
        sampled, _, _ = maybe_flip_z(sampled, None, "auto" if payload.get("z_flipped", True) else "off")
        if sampled.shape == points.shape and np.allclose(sampled, points, atol=1e-6):
            return curve_ids
    except Exception as exc:
        print(f"CAD curve ids unavailable ({exc}); splitting the point cloud by gaps")
    return curve_ids_from_gaps(points)


def save_curves_3d(path: Path, points: np.ndarray, curve_ids: np.ndarray, colors: np.ndarray) -> None:
    fig = plt.figure(figsize=(8, 7), dpi=140)
    ax = fig.add_subplot(111, projection="3d")
    for cid in range(int(curve_ids.max()) + 1 if curve_ids.size else 0):
        mask = curve_ids == cid
        if not np.any(mask):
            continue
        xyz = points[mask]
        color = colors[cid]
        if xyz.shape[0] == 1:
            ax.scatter(xyz[:, 0], xyz[:, 1], xyz[:, 2], color=color, s=12, depthshade=False)
        else:
            ax.plot(xyz[:, 0], xyz[:, 1], xyz[:, 2], color=color, linewidth=1.8)
    _set_axes_equal(ax, points)
    ax.set_xlabel("X")
    ax.set_ylabel("Y")
    ax.set_zlabel("Z")
    ax.set_title(f"GT curves ({int(curve_ids.max()) + 1 if curve_ids.size else 0})")
    ax.view_init(elev=22, azim=-60)
    fig.tight_layout()
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)


def _set_axes_equal(ax, points: np.ndarray) -> None:
    mn = points.min(axis=0)
    mx = points.max(axis=0)
    center = 0.5 * (mn + mx)
    radius = 0.5 * float((mx - mn).max())
    radius = max(radius, 1e-3)
    ax.set_xlim(center[0] - radius, center[0] + radius)
    ax.set_ylim(center[1] - radius, center[1] + radius)
    ax.set_zlim(center[2] - radius, center[2] + radius)


def save_view_overlay(
    path: Path,
    image_path: Path,
    xy: np.ndarray,
    curve_ids_view: np.ndarray,
    colors: np.ndarray,
    view: int,
) -> None:
    image = np.asarray(Image.open(image_path).convert("RGB"))
    height, width = image.shape[:2]
    fig, ax = plt.subplots(figsize=(width / 100, height / 100), dpi=100)
    ax.imshow(image)
    if xy.shape[0]:
        ax.scatter(
            xy[:, 0],
            xy[:, 1],
            c=colors[curve_ids_view],
            s=14,
            linewidths=0,
            marker="o",
        )
    ax.set_xlim(0, width)
    ax.set_ylim(height, 0)
    ax.set_axis_off()
    ax.set_title(f"view {view:02d}", fontsize=11, loc="left", color="black", pad=2)
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, bbox_inches="tight", pad_inches=0.05)
    plt.close(fig)


def save_montage(path: Path, view_paths: list[tuple[int, Path]], columns: int = 10) -> None:
    if not view_paths:
        return
    thumbs = []
    for view, img_path in view_paths:
        im = Image.open(img_path).convert("RGB")
        im.thumbnail((220, 220))
        canvas = Image.new("RGB", (220, 236), (255, 255, 255))
        x = (220 - im.width) // 2
        canvas.paste(im, (x, 16))
        thumbs.append(canvas)
    columns = max(int(columns), 1)
    rows = int(np.ceil(len(thumbs) / columns))
    tw, th = thumbs[0].size
    sheet = Image.new("RGB", (columns * tw, rows * th), (255, 255, 255))
    for i, thumb in enumerate(thumbs):
        r, c = divmod(i, columns)
        sheet.paste(thumb, (c * tw, r * th))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def find_image(object_dir: Path, view: int) -> Path:
    img_dir = Path(object_dir) / "train_img"
    for name in (f"{view}_colors.png", f"{view:02d}_colors.png", f"{view}.png"):
        path = img_dir / name
        if path.exists():
            return path
    raise FileNotFoundError(f"No image for view {view} under {img_dir}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Draw GT curves and their associated 2D edge points in matching colors."
    )
    p.add_argument("--assoc", type=Path, default=DEFAULT_ASSOC, help="GT_3D_2D_assoc_*.json")
    p.add_argument(
        "--object-dir",
        type=Path,
        default=None,
        help="ABC-NEF object folder with train_img/.  "
             "Default: <dataset-root>/<object_id from the JSON>.",
    )
    p.add_argument("--dataset-root", type=Path, default=DEFAULT_DATASET_ROOT)
    p.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="Where figures are written (default: <assoc dir>/vis_<tag>).",
    )
    p.add_argument("--columns", type=int, default=10, help="Montage columns.")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    assoc_path = args.assoc.expanduser().resolve()
    payload = load_association(assoc_path)
    object_id = str(payload["object_id"])
    dataset_root = args.dataset_root.expanduser().resolve()
    object_dir = (
        args.object_dir.expanduser().resolve()
        if args.object_dir is not None
        else dataset_root / object_id
    )
    tag = object_id[-4:]
    out_dir = (
        args.out_dir.expanduser().resolve()
        if args.out_dir is not None
        else assoc_path.parent / f"vis_{tag}"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    points = payload["points"]
    curve_ids = resolve_curve_ids(payload, dataset_root)
    if curve_ids.shape[0] != points.shape[0]:
        raise SystemExit(
            f"curve id count {curve_ids.shape[0]} != point count {points.shape[0]}"
        )
    n_curves = int(curve_ids.max()) + 1 if curve_ids.size else 0
    colors = curve_colors(n_curves)
    print(f"{object_id}: {points.shape[0]} samples, {n_curves} curves")

    curve_path = out_dir / "gt_curves_3d.png"
    save_curves_3d(curve_path, points, curve_ids, colors)
    print(f"wrote {curve_path}")

    by_view = {int(block["view"]): block for block in payload["associations"]}
    view_dir = out_dir / "views"
    saved: list[tuple[int, Path]] = []
    for view in sorted(by_view):
        block = by_view[view]
        point_index = np.asarray(block["point_index"], dtype=int)
        edge_points = np.asarray(block["edge_points"], dtype=float).reshape(-1, 3)
        if point_index.size == 0:
            xy = np.zeros((0, 2))
            cids = np.zeros(0, dtype=int)
        else:
            xy = edge_points[:, :2]
            cids = curve_ids[point_index - 1]
        img_path = find_image(object_dir, view)
        out_path = view_dir / f"view_{view:02d}.png"
        save_view_overlay(out_path, img_path, xy, cids, colors, view)
        saved.append((view, out_path))
        print(f"  view {view:02d}: {xy.shape[0]} edge points -> {out_path.name}")

    montage_path = out_dir / "views_montage.png"
    save_montage(montage_path, saved, columns=args.columns)
    print(f"wrote {montage_path}  ({len(saved)} views)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
