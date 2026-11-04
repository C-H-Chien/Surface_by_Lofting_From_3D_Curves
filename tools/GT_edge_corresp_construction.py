#!/usr/bin/env python3
"""
Associate ground-truth 3D curve samples with detected 2D edge points.

For each view:
  1. Ray-trace camera to 3D curve point against the object mesh (occlusion).
  2. Project visible 3D points and their orientations into the image.
  3. Match each projection to a detected 2D edge point by proximity and
     orientation.  Both tests must pass.

The association is per image: 3D sample ``i`` is tied to the 2D edge point
``(x, y, theta)`` it matches in that view.  ``index_pairs[i, v]`` is the
1-based index of that edge point in ``Edges/Edge_{v}_t1.txt``, or ``-2``
if the sample has no edge point in view ``v``.  The same row order is used
for the stored ``(x, y, theta)`` edge points.

Coordinate conventions (ABC-NEF + refined poses)
------------------------------------------------
Original ABC-NEF rotations are improper (det R = -1).  ``refined_R.txt``
converts them to proper rotations by right-multiplying ``diag(1,1,-1)``,
so GT curve points/tangents sampled in the NEF unit cube (z > 0) must be
Z-flipped before projection.  See ``refine_ABC_NEF_camera_poses``.

The object mesh and feature curves live under the ABC-NEF dataset root
(``feat/``, ``obj/``, ``chunk_0000_feats.json``, ``chunk_0000_stats.json``)
in raw ABC coordinates.  They are scaled + translated into the NEF unit
cube (same transform as ``gen_GT_curve_points.py``, using the stats bbox)
and then Z-flipped to match the refined poses.

GT sampling is done **after** that normalization, at a uniform arc-length
spacing in the unit cube (``--sample-spacing``, default 0.01).
``--sharp-only`` (default on) keeps only feature curves marked ``sharp: true``.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree

MISSING = -2
# ABC-NEF renders 800x800 views.  fx = fy = 1111.11..., principal point at the
# image center.  Overridden by transforms_train.json when that file exists.
ABC_NEF_FX = 1111.1113654242622
ABC_NEF_CX = 399.5
DEFAULT_DATASET_ROOT = Path("/media/chchien/843557f5-9293-49aa-8fb8-c1fc6c72f7ea/home/chchien/datasets/ABC-NEF")
DEFAULT_ABC_NEF_SRC = DEFAULT_DATASET_ROOT
DEFAULT_CORRESP_DIR = Path(__file__).resolve().parents[1] / "tools" / "GT_edge_corresp_ABC_NEF"
LEGACY_ABC_NEF_SRC = Path("/media/chchien/843557f5-9293-49aa-8fb8-c1fc6c72f7ea/home/chchien/datasets/ABC-NEF/obj")

# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def camera_center_world(R: np.ndarray, t: np.ndarray) -> np.ndarray:
    """World-frame camera center for world-to-camera ``X_c = R X_w + t``."""
    R = np.asarray(R, dtype=float).reshape(3, 3)
    t = np.asarray(t, dtype=float).reshape(3)
    return (-R.T @ t).reshape(3)


def project_points_and_tangents( points_3d: np.ndarray, tangents_3d: np.ndarray, K: np.ndarray, R: np.ndarray, t: np.ndarray ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Project 3D oriented samples into pixel space.
    Outputs:
    xy : (N, 2) Pixel coordinates.  Invalid rows are NaN.
    t2d : (N, 2) Unit pixel-space tangent (undirected; sign is arbitrary).
    valid : (N,) bool
        True iff the point is in the camera's viewing half-space (positive
        OpenCV z *or* negative OpenGL z, auto-detected from the cloud) and
        the projected tangent is non-degenerate.
    """
    X = np.asarray(points_3d, dtype=float).reshape(-1, 3)
    D = np.asarray(tangents_3d, dtype=float).reshape(-1, 3)
    K = np.asarray(K, dtype=float).reshape(3, 3)
    R = np.asarray(R, dtype=float).reshape(3, 3)
    t = np.asarray(t, dtype=float).reshape(3)

    Xc = (R @ X.T).T + t
    z = Xc[:, 2]
    # ABC-NEF refined poses keep the OpenGL look-down-(-Z) convention, so
    # visible points have *negative* camera z.  OpenCV-style poses have
    # positive z.  Keep whichever half-space contains the sample cloud.
    finite_z = np.abs(z) > 1e-8
    if np.any(finite_z):
        z_ref = float(np.median(z[finite_z]))
        in_front = finite_z & ((z * z_ref) > 0.0)
    else:
        in_front = finite_z

    gammas = np.full_like(Xc, np.nan)
    gammas[in_front] = Xc[in_front] / z[in_front, None]

    pix = gammas @ K.T
    xy = np.full((X.shape[0], 2), np.nan)
    xy[in_front] = pix[in_front, :2] / pix[in_front, 2:3]

    # Analytic projection of a 3D tangent onto the image plane.
    # Finite-differencing X vs X+eps*d is only a first-order approximation
    # and breaks when the offset sample goes behind the camera.
    Td = (R @ D.T).T
    proj = Td - Td[:, 2:3] * gammas
    fx, fy = float(K[0, 0]), float(K[1, 1])
    t2d = np.column_stack([fx * proj[:, 0], fy * proj[:, 1]])
    nrm = np.linalg.norm(t2d, axis=1)
    valid_t = nrm > 1e-12
    t2d = np.divide(t2d, nrm[:, None], out=np.zeros_like(t2d), where=valid_t[:, None])
    return xy, t2d, in_front & valid_t


def in_image_mask(xy: np.ndarray, width: int, height: int, margin: float = 0.0) -> np.ndarray:
    x, y = xy[:, 0], xy[:, 1]
    return (
        np.isfinite(x)
        & np.isfinite(y)
        & (x >= margin)
        & (y >= margin)
        & (x < width - margin)
        & (y < height - margin)
    )


# ---------------------------------------------------------------------------
# Mesh I/O and ABC-NEF normalization
# ---------------------------------------------------------------------------
def load_obj_mesh(path: Path) -> tuple[np.ndarray, np.ndarray]:
    """Minimal OBJ loader (vertices + triangulated faces).  1-based OBJ indices."""
    vertices: list[list[float]] = []
    faces: list[list[int]] = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("v "):
                parts = line.split()
                vertices.append([float(parts[1]), float(parts[2]), float(parts[3])])
            elif line.startswith("f "):
                idx = [int(p.split("/")[0]) - 1 for p in line.split()[1:]]
                for i in range(1, len(idx) - 1):
                    faces.append([idx[0], idx[i], idx[i + 1]])
    if not vertices or not faces:
        raise ValueError(f"No triangle mesh in {path}")
    return np.asarray(vertices, dtype=np.float64), np.asarray(faces, dtype=np.int32)

def abc_nef_normalize_vertices( vertices: np.ndarray, bbox: list[float], flip_z: bool ) -> np.ndarray:
    """Map raw ABC vertices into the NEF unit-cube frame used by the GT curves.

    Matches ``evaluation/gen_GT_curve_points.py``:
        scale = 1 / max(x_range, y_range, z_range)
        set_location = [0.5, 0.5, 0.5] - scale * bbox_center
        v' = scale * v + set_location
    Then optionally Z-flip to match refined (proper) camera poses.
    """
    x_min, y_min, z_min, x_max, y_max, z_max, x_range, y_range, z_range = bbox
    scale = 1.0 / max(x_range, y_range, z_range)
    poi_center = np.array( [(x_min + x_max) / 2.0, (y_min + y_max) / 2.0, (z_min + z_max) / 2.0] ) * scale
    set_location = np.array([0.5, 0.5, 0.5]) - poi_center
    out = np.asarray(vertices, dtype=np.float64) * scale + set_location
    if flip_z:
        out = out.copy()
        out[:, 2] *= -1.0
    return out


def bbox_from_vertices(vertices: np.ndarray) -> list[float]:
    """AABB in the 9-value layout used by ``chunk_0000_stats.json``."""
    v = np.asarray(vertices, dtype=float).reshape(-1, 3)
    mn = v.min(axis=0)
    mx = v.max(axis=0)
    rng = mx - mn
    return [
        float(mn[0]), float(mn[1]), float(mn[2]),
        float(mx[0]), float(mx[1]), float(mx[2]),
        float(rng[0]), float(rng[1]), float(rng[2]),
    ]

def load_nef_bbox( abc_src: Path, object_id: str, vertices: np.ndarray | None = None ) -> tuple[list[float], str]:
    """NEF unit-cube bbox from ``chunk_0000_stats.json``, else the mesh AABB."""
    candidates = [
        Path(abc_src) / "chunk_0000_stats.json",
        DEFAULT_DATASET_ROOT / "chunk_0000_stats.json",
        LEGACY_ABC_NEF_SRC / "chunk_0000_stats.json",
    ]
    seen: set[Path] = set()
    for path in candidates:
        path = path.expanduser().resolve()
        if path in seen or not path.exists():
            continue
        seen.add(path)
        with open(path) as f:
            stats = json.load(f)
        if object_id in stats and "bbox" in stats[object_id]:
            return list(stats[object_id]["bbox"]), str(path)
    if vertices is not None and len(vertices) > 0:
        return bbox_from_vertices(vertices), "mesh-aabb"
    raise FileNotFoundError(
        f"No bbox for {object_id}: looked for chunk_0000_stats.json under "
        f"{abc_src} and {LEGACY_ABC_NEF_SRC}, and no mesh vertices were given"
    )

def find_abc_obj(abc_src: Path, object_id: str) -> Path:
    obj_dir = Path(abc_src) / "obj"
    matches = sorted(obj_dir.glob(f"{object_id}_*.obj"))
    if not matches:
        raise FileNotFoundError(
            f"No mesh matching {object_id}_*.obj under {obj_dir}"
        )
    return matches[0]

def find_abc_feat(abc_src: Path, object_id: str) -> Path:
    feat_dir = Path(abc_src) / "feat"
    matches = sorted(feat_dir.glob(f"{object_id}_*.yml")) + sorted(
        feat_dir.glob(f"{object_id}_*.yaml")
    )
    if not matches:
        raise FileNotFoundError(
            f"No feature YAML matching {object_id}_*.yml under {feat_dir}"
        )
    return matches[0]


def load_feature_curves(abc_src: Path, object_id: str) -> list[dict]:
    """Load ``{sharp, vert_indices}`` per CAD curve from ABC-NEF feats.

    Prefers ``chunk_0000_feats.json``; falls back to feat YAML.
    """
    json_path = Path(abc_src) / "chunk_0000_feats.json"
    if json_path.exists():
        with open(json_path) as f:
            feats = json.load(f)
        if object_id not in feats:
            raise KeyError(f"{object_id} not in {json_path}")
        return [
            {
                "sharp": bool(c.get("sharp")),
                "vert_indices": list(c["vert_indices"]),
            }
            for c in feats[object_id]
        ]
    yml = find_abc_feat(abc_src, object_id)
    return _parse_feat_yml(yml)


def _parse_feat_yml(path: Path) -> list[dict]:
    """Minimal parser for ABC-NEF ``*_features_*.yml`` (no PyYAML required).

    Only the top-level ``curves:`` list is read.  The following ``surfaces:``
    block also contains ``vert_indices`` (tessellated faces) and must not be
    treated as feature curves.
    """
    import re

    lines = Path(path).read_text(encoding="utf-8").splitlines()
    try:
        c0 = next(i for i, ln in enumerate(lines) if ln.startswith("curves:"))
    except StopIteration as exc:
        raise ValueError(f"No 'curves:' section in {path}") from exc
    c1 = len(lines)
    for i in range(c0 + 1, len(lines)):
        if re.match(r"^[A-Za-z]", lines[i]):
            c1 = i
            break
    section = lines[c0 + 1:c1]
    starts = [i for i, ln in enumerate(section) if ln.startswith("- ")]
    if not starts:
        raise ValueError(f"No curves in {path}")
    starts.append(len(section))
    curves: list[dict] = []
    for a, b in zip(starts, starts[1:]):
        block = "\n".join(section[a:b])
        sharp_m = re.search(r"^\s*sharp:\s*(true|false)", block, re.I | re.M)
        idx_m = re.search(r"vert_indices:\s*\[(.*?)\]", block, re.S)
        if idx_m is None:
            continue
        idx_txt = idx_m.group(1).replace("\n", " ")
        vert_indices = [int(x) for x in re.findall(r"-?\d+", idx_txt)]
        curves.append({
            "sharp": bool(sharp_m and sharp_m.group(1).lower() == "true"),
            "vert_indices": vert_indices,
        })
    if not curves:
        raise ValueError(f"No vert_indices in {path}")
    return curves


def sample_polyline_arclength( vertices: np.ndarray, spacing: float ) -> tuple[np.ndarray, np.ndarray]:
    """Uniform arc-length samples along a polyline already in the unit cube.

    Always includes the start point; includes the end if it is farther than
    ``0.25 * spacing`` from the last sample.  Short curves still contribute
    their vertices.
    """
    verts = np.asarray(vertices, dtype=float).reshape(-1, 3)
    if verts.shape[0] == 0:
        return np.zeros((0, 3)), np.zeros((0, 3))
    if verts.shape[0] == 1:
        return verts.copy(), np.array([[1.0, 0.0, 0.0]])

    step = np.linalg.norm(np.diff(verts, axis=0), axis=1)
    keep = np.concatenate([[True], step > 1e-12])
    verts = verts[keep]
    if verts.shape[0] == 1:
        return verts.copy(), np.array([[1.0, 0.0, 0.0]])

    seg = verts[1:] - verts[:-1]
    seglen = np.linalg.norm(seg, axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seglen)])
    total = float(cum[-1])
    spacing = float(spacing)
    if spacing <= 0:
        raise ValueError(f"sample spacing must be positive, got {spacing}")
    if total < 1e-12:
        return verts[:1].copy(), np.array([[1.0, 0.0, 0.0]])

    n = int(np.floor(total / spacing))
    s = np.arange(n + 1, dtype=float) * spacing
    if s[-1] > total:
        s[-1] = total
    if total - s[-1] > 0.25 * spacing:
        s = np.append(s, total)

    idx = np.clip(np.searchsorted(cum, s, side="right") - 1, 0, len(seglen) - 1)
    local = s - cum[idx]
    denom = np.maximum(seglen[idx], 1e-12)
    alpha = np.clip(local / denom, 0.0, 1.0)
    points = verts[idx] + alpha[:, None] * seg[idx]
    tangents = seg[idx] / denom[:, None]
    return points, tangents


def sample_gt_curves_from_cad(
    abc_src: Path,
    object_id: str,
    *,
    sharp_only: bool = True,
    sample_spacing: float = 0.01,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, dict]:
    """Sample oriented 3D curve points in the NEF unit cube from obj+feat.

    Vertices are normalized first (same transform as the published GT txt
    files); arc-length sampling then uses ``sample_spacing`` in that cube,
    so large raw ABC models do not explode in point count.

    ``curve_ids[i]`` is the 0-based index of the CAD curve that sample ``i``
    belongs to, in the order curves are kept.
    """
    abc_src = Path(abc_src)
    obj_path = find_abc_obj(abc_src, object_id)
    vertices, _faces = load_obj_mesh(obj_path)
    bbox, bbox_src = load_nef_bbox(abc_src, object_id, vertices)
    vertices = abc_nef_normalize_vertices(vertices, bbox, flip_z=False)

    curves = load_feature_curves(abc_src, object_id)
    pts_list: list[np.ndarray] = []
    tng_list: list[np.ndarray] = []
    id_list: list[np.ndarray] = []
    n_sharp = 0
    n_used = 0
    for curve in curves:
        is_sharp = bool(curve.get("sharp"))
        if is_sharp:
            n_sharp += 1
        if sharp_only and not is_sharp:
            continue
        idx = np.asarray(curve["vert_indices"], dtype=int)
        if idx.size < 1:
            continue
        if np.any(idx < 0) or np.any(idx >= len(vertices)):
            raise IndexError(
                f"{object_id}: vert_indices out of range for {obj_path}"
            )
        poly = vertices[idx]
        p, t = sample_polyline_arclength(poly, sample_spacing)
        if p.shape[0] == 0:
            continue
        pts_list.append(p)
        tng_list.append(t)
        id_list.append(np.full(p.shape[0], n_used, dtype=np.int32))
        n_used += 1

    if not pts_list:
        raise ValueError(
            f"{object_id}: no curve samples "
            f"(sharp_only={sharp_only}, n_curves={len(curves)}, n_sharp={n_sharp})"
        )
    points = np.concatenate(pts_list, axis=0)
    tangents = np.concatenate(tng_list, axis=0)
    curve_ids = np.concatenate(id_list, axis=0)
    nrm = np.linalg.norm(tangents, axis=1, keepdims=True)
    tangents = np.divide(tangents, np.maximum(nrm, 1e-12))
    meta = {
        "n_cad_curves": len(curves),
        "n_sharp_curves": n_sharp,
        "n_used_curves": n_used,
        "sharp_only": bool(sharp_only),
        "sample_spacing": float(sample_spacing),
        "source": str(obj_path),
        "bbox_source": bbox_src,
    }
    return points, tangents, curve_ids, meta


def maybe_flip_z( points: np.ndarray, tangents: np.ndarray | None, mode: str ) -> tuple[np.ndarray, np.ndarray | None, bool]:
    """Z-flip GT samples so they agree with refined (proper) rotations.
    ``auto``: flip if the cloud sits in the NEF unit cube with predominantly
    positive z.  Files that are already flipped are left alone.
    """
    if mode not in ("auto", "on", "off"):
        raise ValueError(f"flip_z mode must be auto/on/off, got {mode!r}")
    do_flip = (mode == "on") or (
        mode == "auto" and float(np.median(points[:, 2])) > 0.0
    )
    if not do_flip:
        return points, tangents, False
    points = np.array(points, copy=True)
    points[:, 2] *= -1.0
    if tangents is not None:
        tangents = np.array(tangents, copy=True)
        tangents[:, 2] *= -1.0
    return points, tangents, True


def estimate_tangents(points: np.ndarray, break_factor: float = 3.0) -> np.ndarray:
    """Unit tangents from consecutive samples, splitting at curve gaps."""
    points = np.asarray(points, dtype=float).reshape(-1, 3)
    n = points.shape[0]
    if n == 0:
        return np.zeros((0, 3))
    if n == 1:
        return np.array([[1.0, 0.0, 0.0]])

    step = np.linalg.norm(np.diff(points, axis=0), axis=1)
    positive = step[step > 0]
    med = float(np.median(positive)) if positive.size else 0.01
    # is_break[k] = gap between point k-1 and k (is_break[0] marks the start).
    is_break = np.concatenate([[True], step > break_factor * max(med, 1e-12)])

    tangents = np.zeros_like(points)
    i = 0
    while i < n:
        j = i + 1
        while j < n and not is_break[j]:
            j += 1
        if j - i == 1:
            tangents[i] = np.array([1.0, 0.0, 0.0])
        else:
            delta = points[i + 1:j] - points[i:j - 1]
            fwd = np.vstack([delta, delta[-1]])
            bwd = np.vstack([delta[0], delta])
            d = fwd + bwd
            nrm = np.linalg.norm(d, axis=1, keepdims=True)
            ok = nrm[:, 0] > 1e-12
            idx = np.arange(i, j)
            tangents[idx[ok]] = d[ok] / nrm[ok]
            if not np.all(ok):
                fn = np.linalg.norm(fwd, axis=1, keepdims=True)
                f_ok = (~ok) & (fn[:, 0] > 1e-12)
                tangents[idx[f_ok]] = fwd[f_ok] / fn[f_ok]
        i = j
    nrm = np.linalg.norm(tangents, axis=1, keepdims=True)
    bad = nrm[:, 0] <= 1e-12
    tangents[bad] = np.array([1.0, 0.0, 0.0])
    tangents = np.divide(tangents, nrm, out=tangents, where=~bad[:, None])
    return tangents


def _loadtxt_xyz(path: Path) -> np.ndarray:
    """Load a numeric table that may be comma- or whitespace-separated."""
    try:
        raw = np.loadtxt(path, delimiter=",")
        if raw.ndim == 1:
            raw = raw[None, :]
        if raw.shape[1] >= 3:
            return raw
    except Exception:
        pass
    raw = np.loadtxt(path)
    if raw.ndim == 1:
        raw = raw[None, :]
    return raw


def load_gt_curves(
    path: Path,
    directions_path: Path | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    """Load GT curve samples.  Accepts 3-col xyz or 6-col xyz+direction."""
    raw = _loadtxt_xyz(path)
    if raw.shape[1] >= 6:
        points, tangents = raw[:, :3], raw[:, 3:6]
    elif raw.shape[1] == 3:
        points = raw[:, :3]
        if directions_path is not None:
            tangents = _loadtxt_xyz(directions_path)[:, :3]
            if tangents.shape[0] != points.shape[0]:
                raise ValueError(
                    f"Direction count {tangents.shape[0]} != point count {points.shape[0]}"
                )
        else:
            tangents = estimate_tangents(points)
    else:
        raise ValueError(f"{path} must have 3 or 6 columns, got {raw.shape[1]}")

    nrm = np.linalg.norm(tangents, axis=1, keepdims=True)
    tangents = np.divide(tangents, np.maximum(nrm, 1e-12))
    return np.asarray(points, dtype=float), np.asarray(tangents, dtype=float)


# ---------------------------------------------------------------------------
# Visibility (ray tracing)
# ---------------------------------------------------------------------------

def _mt_hits_before(
    origin: np.ndarray,
    direction: np.ndarray,
    v0: np.ndarray,
    v1: np.ndarray,
    v2: np.ndarray,
    t_max: float,
    t_floor: float = 1e-8,
) -> bool:
    """True if any of the K triangles is hit on (t_floor, t_max]."""
    if v0.shape[0] == 0:
        return False
    e1 = v1 - v0
    e2 = v2 - v0
    pvec = np.cross(direction, e2)
    det = np.einsum("ki,ki->k", pvec, e1)
    valid = np.abs(det) > 1e-12
    if not np.any(valid):
        return False
    inv = np.zeros_like(det)
    np.divide(1.0, det, out=inv, where=valid)
    tvec = origin - v0
    u = np.einsum("ki,ki->k", tvec, pvec) * inv
    valid &= (u >= 0.0) & (u <= 1.0)
    qvec = np.cross(tvec, e1)
    v = np.einsum("i,ki->k", direction, qvec) * inv
    valid &= (v >= 0.0) & (u + v <= 1.0)
    t = np.einsum("ki,ki->k", qvec, e2) * inv
    valid &= (t > t_floor) & (t <= t_max)
    return bool(np.any(valid))


class MeshRayTracer:
    """First-hit ray queries.  Prefers trimesh/embree; otherwise a uniform grid."""

    def __init__(self, vertices: np.ndarray, faces: np.ndarray, grid_res: int = 48):
        self.vertices = np.asarray(vertices, dtype=np.float64)
        self.faces = np.asarray(faces, dtype=np.int32)
        self.v0 = self.vertices[self.faces[:, 0]]
        self.v1 = self.vertices[self.faces[:, 1]]
        self.v2 = self.vertices[self.faces[:, 2]]
        self._intersector = None
        self._use_trimesh = False
        intersector = self._try_trimesh_intersector()
        if intersector is not None:
            self._intersector = intersector
            self._use_trimesh = True
            self.backend = "trimesh"
        else:
            self.backend = "grid"
            self._build_grid(grid_res)

    def _try_trimesh_intersector(self):
        """Embree if present, else trimesh+rtree.  None when neither is usable."""
        try:
            import trimesh
        except ImportError:
            return None
        mesh = trimesh.Trimesh(
            vertices=self.vertices, faces=self.faces, process=False
        )
        candidates = []
        try:
            from trimesh.ray.ray_pyembree import RayMeshIntersector as _RMI
            candidates.append(_RMI(mesh))
        except Exception:
            pass
        try:
            import rtree  # noqa: F401
            candidates.append(mesh.ray)
        except Exception:
            pass
        origin = np.asarray(self.vertices[:1], dtype=float)
        direction = np.array([[0.0, 0.0, 1.0]])
        for intersector in candidates:
            try:
                intersector.intersects_location(
                    ray_origins=origin,
                    ray_directions=direction,
                    multiple_hits=False,
                )
                return intersector
            except TypeError:
                try:
                    intersector.intersects_location(
                        ray_origins=origin,
                        ray_directions=direction,
                    )
                    return intersector
                except Exception:
                    continue
            except Exception:
                continue
        return None

    def _build_grid(self, resolution: int) -> None:
        verts = self.vertices
        pad = 1e-6
        self.origin = verts.min(axis=0) - pad
        self.span = verts.max(axis=0) - self.origin + 2 * pad
        self.res = int(resolution)
        self.cell = self.span / self.res
        ncells = self.res ** 3
        cells: list[list[int]] = [[] for _ in range(ncells)]
        tmin = np.minimum(np.minimum(self.v0, self.v1), self.v2)
        tmax = np.maximum(np.maximum(self.v0, self.v1), self.v2)
        i0 = np.clip(((tmin - self.origin) / self.cell).astype(int), 0, self.res - 1)
        i1 = np.clip(((tmax - self.origin) / self.cell).astype(int), 0, self.res - 1)
        res = self.res
        for fi in range(self.faces.shape[0]):
            x0, y0, z0 = (int(i0[fi, 0]), int(i0[fi, 1]), int(i0[fi, 2]))
            x1, y1, z1 = (int(i1[fi, 0]), int(i1[fi, 1]), int(i1[fi, 2]))
            for ix in range(x0, x1 + 1):
                for iy in range(y0, y1 + 1):
                    for iz in range(z0, z1 + 1):
                        cells[ix + res * (iy + res * iz)].append(fi)
        self.cells = [np.asarray(c, dtype=np.int32) for c in cells]

    def _cell_id(self, ix: int, iy: int, iz: int) -> int:
        return ix + self.res * (iy + self.res * iz)

    def _grid_occluded(self, origin: np.ndarray, direction: np.ndarray, t_max: float) -> bool:
        """True if the mesh is hit on (0, t_max] along this unit-direction ray."""
        inv = np.empty(3)
        for k in range(3):
            inv[k] = 1.0 / direction[k] if abs(direction[k]) > 1e-15 else 1e15
        bmin = self.origin
        bmax = self.origin + self.span
        t1 = (bmin - origin) * inv
        t2 = (bmax - origin) * inv
        t_enter = float(np.maximum(np.minimum(t1, t2), 0.0).max())
        t_exit = float(np.minimum(np.maximum(t1, t2), t_max).min())
        if t_enter > t_exit:
            return False

        pos = origin + (t_enter + 1e-8) * direction
        voxel = np.floor((pos - self.origin) / self.cell).astype(int)
        voxel = np.clip(voxel, 0, self.res - 1)
        step = np.sign(direction).astype(int)
        step[step == 0] = 1
        next_b = self.origin + (voxel + (step > 0).astype(int)) * self.cell
        t_next = (next_b - origin) * inv
        t_delta = np.abs(self.cell * inv)

        tested: set[int] = set()
        res = self.res
        while True:
            ix, iy, iz = int(voxel[0]), int(voxel[1]), int(voxel[2])
            if not (0 <= ix < res and 0 <= iy < res and 0 <= iz < res):
                return False
            tris = self.cells[self._cell_id(ix, iy, iz)]
            if tris.size:
                new = [int(fi) for fi in tris if int(fi) not in tested]
                if new:
                    tested.update(new)
                    idx = np.asarray(new, dtype=np.int32)
                    if _mt_hits_before(
                        origin, direction,
                        self.v0[idx], self.v1[idx], self.v2[idx], t_max,
                    ):
                        return True
            axis = int(np.argmin(t_next))
            if t_next[axis] > t_exit + 1e-9:
                return False
            voxel[axis] += int(step[axis])
            t_next[axis] += t_delta[axis]

    def first_hit_t(
        self,
        origins: np.ndarray,
        directions: np.ndarray,
        t_max: np.ndarray,
    ) -> np.ndarray:
        n = origins.shape[0]
        t_hit = np.full(n, np.inf)
        if self._use_trimesh:
            try:
                locations, ray_idx, _ = self._intersector.intersects_location(
                    ray_origins=origins,
                    ray_directions=directions,
                    multiple_hits=False,
                )
            except TypeError:
                locations, ray_idx, _ = self._intersector.intersects_location(
                    ray_origins=origins,
                    ray_directions=directions,
                )
            if len(ray_idx):
                dist = np.linalg.norm(locations - origins[np.asarray(ray_idx)], axis=1)
                order = np.argsort(dist)
                dist_sorted = dist[order]
                ray_sorted = np.asarray(ray_idx)[order]
                _, first = np.unique(ray_sorted, return_index=True)
                t_hit[ray_sorted[first]] = dist_sorted[first]
            return t_hit

        for i in range(n):
            if t_max[i] <= 0:
                continue
            if self._grid_occluded(origins[i], directions[i], float(t_max[i])):
                t_hit[i] = 0.0  # any hit before t_max counts as occluded
        return t_hit


def points_visible_by_raytrace(
    points_3d: np.ndarray,
    cam_center: np.ndarray,
    vertices: np.ndarray,
    faces: np.ndarray,
    rel_eps: float = 1e-3,
    abs_eps: float = 1e-4,
    tracer: MeshRayTracer | None = None,
) -> np.ndarray:
    """Visibility of surface samples by shooting a ray from the camera.

    A sample is visible iff the first mesh intersection is at (or behind)
    the sample, not strictly in front of it.

    Curve samples lie *on* the surface, so the supporting triangle is
    expected to be the first hit.  We shorten the allowed hit distance by
    ``offset = clip(rel_eps * dist, abs_eps, ...)`` toward the camera so
    that triangle is not counted as an occluder (self-hit / z-fighting).
    A true occluder sits well in front of that offset.
    """
    points_3d = np.asarray(points_3d, dtype=float).reshape(-1, 3)
    cam_center = np.asarray(cam_center, dtype=float).reshape(3)
    n = points_3d.shape[0]
    if n == 0:
        return np.zeros(0, dtype=bool)

    ray_dirs = points_3d - cam_center
    dists = np.linalg.norm(ray_dirs, axis=1)
    too_close = dists < 1e-8
    ray_dirs_n = np.divide(
        ray_dirs,
        dists[:, None],
        out=np.zeros_like(ray_dirs),
        where=~too_close[:, None],
    )

    offset = np.clip(rel_eps * dists, abs_eps, 0.02)
    t_max = np.maximum(dists - offset, 0.0)

    origins = np.broadcast_to(cam_center, points_3d.shape).copy()
    if tracer is None:
        tracer = MeshRayTracer(vertices, faces)
    t_hit = tracer.first_hit_t(origins, ray_dirs_n, t_max)

    # Visible if nothing is strictly in front of the offset query.
    # Grid backend reports occluded rays as t_hit == 0.
    visible = (~too_close) & (t_hit >= t_max - abs_eps)
    return visible


# ---------------------------------------------------------------------------
# 2D matching
# ---------------------------------------------------------------------------

def edgel_unit_tangents(edgels: np.ndarray) -> np.ndarray:
    """ABC-NEF ``Edge_*_t1.txt`` stores orientation as an angle in column 2."""
    theta = np.asarray(edgels, dtype=float)[:, 2]
    return np.column_stack([np.cos(theta), np.sin(theta)])


def match_projections_to_edgels(
    xy: np.ndarray,
    t2d: np.ndarray,
    edges_xy: np.ndarray,
    edges_t: np.ndarray,
    dist_thresh: float,
    cos_thresh: float,
    unique_2d: bool = True,
    knn: int = 32,
) -> np.ndarray:
    """One 2D edgel index per projected 3D sample, or -1 if unmatched.

    Selection: among 2D edgels within ``dist_thresh`` pixels whose unit
    tangent satisfies ``|t2d · t_edgel| >= cos_thresh`` (180° ambiguity),
    take the spatially closest.  If ``unique_2d``, a 2D edgel is assigned
    to at most one 3D sample (greedy by distance) so neighbouring curve
    samples do not all claim the same detection.
    """
    n3 = xy.shape[0]
    assigned = np.full(n3, -1, dtype=int)
    if n3 == 0 or edges_xy.shape[0] == 0:
        return assigned

    k = int(min(max(knn, 1), edges_xy.shape[0]))
    tree = cKDTree(edges_xy)
    dists, nns = tree.query(xy, k=k)
    if k == 1:
        dists = np.asarray(dists).reshape(-1, 1)
        nns = np.asarray(nns).reshape(-1, 1)

    candidates: list[tuple[float, int, int]] = []
    for i in range(n3):
        for j in range(k):
            d = float(dists[i, j])
            if not np.isfinite(d) or d > dist_thresh:
                break
            j2 = int(nns[i, j])
            if abs(float(np.dot(edges_t[j2], t2d[i]))) >= cos_thresh:
                candidates.append((d, i, j2))
                if not unique_2d:
                    assigned[i] = j2
                    break

    if not unique_2d:
        return assigned

    candidates.sort()
    used_3d = np.zeros(n3, dtype=bool)
    used_2d = np.zeros(edges_xy.shape[0], dtype=bool)
    for d, i, j2 in candidates:
        if used_3d[i] or used_2d[j2]:
            continue
        assigned[i] = j2
        used_3d[i] = True
        used_2d[j2] = True
    return assigned


def resolve_curve_depth_ties(
    edge_idx: np.ndarray,
    curve_ids: np.ndarray,
    depths: np.ndarray,
    edge_xy: np.ndarray,
    margin: float,
    pixel_radius: float,
) -> tuple[np.ndarray, int]:
    """Keep the closest curve when several curves fall on the same image edge.

    Two matches compete when their 2D edge points are within ``pixel_radius``
    pixels, which covers both the identical detection and its neighbors along
    the boundary.  Samples of one curve may still share those edge points.
    The farther curve is dropped only when it is more than ``margin`` world
    units behind the closer one, so a corner at the same depth stays tied.
    ``margin < 0`` leaves every match in place.

    ``edge_xy`` is the full edgel array ``(M, 2)`` for this view.
    Returns updated 0-based edgel indices and how many samples were cleared.
    """
    edge_idx = np.asarray(edge_idx, dtype=int).copy()
    curve_ids = np.asarray(curve_ids, dtype=int).reshape(-1)
    depths = np.asarray(depths, dtype=float).reshape(-1)
    edge_xy = np.asarray(edge_xy, dtype=float).reshape(-1, 2)
    claimed = np.flatnonzero(edge_idx >= 0)
    if claimed.size == 0 or margin < 0 or pixel_radius < 0:
        return edge_idx, 0

    xy = edge_xy[edge_idx[claimed]]
    cids = curve_ids[claimed]
    dep = depths[claimed]
    neighbors = cKDTree(xy).query_ball_point(xy, float(pixel_radius))
    drop = np.zeros(claimed.size, dtype=bool)
    for i, nb in enumerate(neighbors):
        di = float(dep[i])
        ci = int(cids[i])
        for j in nb:
            if int(cids[j]) == ci:
                continue
            if float(dep[j]) + float(margin) < di:
                drop[i] = True
                break
    edge_idx[claimed[drop]] = -1
    return edge_idx, int(np.count_nonzero(drop))


def construct_correspondences_one_view(
    points_3d: np.ndarray,
    tangents_3d: np.ndarray,
    K: np.ndarray,
    R: np.ndarray,
    t: np.ndarray,
    edgels: np.ndarray,
    vertices: np.ndarray | None,
    faces: np.ndarray | None,
    dist_thresh: float,
    cos_thresh: float,
    image_size: tuple[int, int],
    unique_2d: bool = True,
    do_raytrace: bool = True,
    rel_eps: float = 1e-3,
    abs_eps: float = 1e-4,
    tracer: MeshRayTracer | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    """Match GT 3D samples to 2D edgels in a single view.

    Returns
    -------
    edge_idx : (N,) int
        0-based 2D edgel index, or -1 if unmatched.
    visible : (N,) bool
        Visibility after the in-front / in-image / ray-trace gates.
    """
    n = points_3d.shape[0]
    edge_idx = np.full(n, -1, dtype=int)
    width, height = image_size

    xy, t2d, valid = project_points_and_tangents(points_3d, tangents_3d, K, R, t)
    valid = valid & in_image_mask(xy, width, height)
    visible = valid.copy()

    if do_raytrace:
        if vertices is None or faces is None:
            raise ValueError("Ray tracing requested but no mesh was loaded.")
        cand = np.flatnonzero(valid)
        if cand.size:
            vis_c = points_visible_by_raytrace(
                points_3d[cand],
                camera_center_world(R, t),
                vertices,
                faces,
                rel_eps=rel_eps,
                abs_eps=abs_eps,
                tracer=tracer,
            )
            visible[cand] = vis_c

    keep = np.flatnonzero(visible)
    if keep.size == 0:
        return edge_idx, visible

    edges_xy = np.asarray(edgels, dtype=float)[:, :2]
    edges_t = edgel_unit_tangents(edgels)
    matched = match_projections_to_edgels(
        xy[keep],
        t2d[keep],
        edges_xy,
        edges_t,
        dist_thresh=dist_thresh,
        cos_thresh=cos_thresh,
        unique_2d=unique_2d,
    )
    hit = matched >= 0
    edge_idx[keep[hit]] = matched[hit]
    return edge_idx, visible


# ---------------------------------------------------------------------------
# I/O / CLI
# ---------------------------------------------------------------------------

def default_intrinsics(object_dir: Path | None = None) -> np.ndarray:
    """3x3 K.  Prefer the intrinsics stored with the rendered views."""
    if object_dir is not None:
        for name in ("transforms_train.json", "transforms_val.json"):
            path = Path(object_dir) / name
            if not path.exists():
                continue
            with open(path) as f:
                payload = json.load(f)
            frames = payload.get("frames") or []
            if frames and "camera_intrinsics" in frames[0]:
                return np.asarray(frames[0]["camera_intrinsics"], dtype=float).reshape(3, 3)
    return np.array(
        [
            [ABC_NEF_FX, 0.0, ABC_NEF_CX],
            [0.0, ABC_NEF_FX, ABC_NEF_CX],
            [0.0, 0.0, 1.0],
        ],
        dtype=float,
    )


def load_Rt(object_dir: Path, view: int) -> tuple[np.ndarray, np.ndarray]:
    """World-to-camera ``R`` (3x3) and ``t`` (3,) for one view.

    Prefers the refined proper rotations.  Both files stack one view after
    another: ``R`` is ``(3V, 3)`` and ``t`` is ``3V`` numbers.
    """
    rnt = Path(object_dir) / "RnT"
    r_path = rnt / "refined_R.txt"
    t_path = rnt / "refined_T.txt"
    if not r_path.exists():
        r_path = rnt / "R_matrix.txt"
        t_path = rnt / "T_matrix.txt"
    if not r_path.exists() or not t_path.exists():
        raise FileNotFoundError(f"No camera pose for view {view} under {rnt}")
    R_all = np.loadtxt(r_path)
    t_all = np.loadtxt(t_path).reshape(-1)
    R = np.asarray(R_all[3 * view: 3 * view + 3], dtype=float).reshape(3, 3)
    t = np.asarray(t_all[3 * view: 3 * view + 3], dtype=float).reshape(3)
    return R, t


def load_edgels(object_dir: Path, view_ids: list[int]) -> dict[int, np.ndarray]:
    """Load ``Edges/Edge_{v}_t1.txt`` as ``(M, >=3)`` rows ``(x, y, theta, ...)``."""
    edges_dir = Path(object_dir) / "Edges"
    out: dict[int, np.ndarray] = {}
    for v in view_ids:
        path = edges_dir / f"Edge_{v}_t1.txt"
        if not path.exists():
            raise FileNotFoundError(f"Missing edgels for view {v}: {path}")
        raw = np.loadtxt(path)
        if raw.ndim == 1:
            raw = raw.reshape(1, -1)
        if raw.shape[1] < 3:
            raise ValueError(
                f"{path} needs at least 3 columns (x, y, theta), got {raw.shape[1]}"
            )
        out[int(v)] = np.asarray(raw, dtype=float)
    return out


def curve_ids_from_gaps(points: np.ndarray, break_factor: float = 3.0) -> np.ndarray:
    """Label consecutive samples that belong to one polyline.

    A new curve starts where the step is much larger than the median step.
    Used when a pre-sampled cloud has no CAD curve index.
    """
    points = np.asarray(points, dtype=float).reshape(-1, 3)
    n = points.shape[0]
    ids = np.zeros(n, dtype=np.int32)
    if n <= 1:
        return ids
    step = np.linalg.norm(np.diff(points, axis=0), axis=1)
    positive = step[step > 0]
    med = float(np.median(positive)) if positive.size else 0.01
    is_break = np.concatenate([[True], step > break_factor * max(med, 1e-12)])
    cid = 0
    for i in range(n):
        if i > 0 and is_break[i]:
            cid += 1
        ids[i] = cid
    return ids


def write_gt_edge_corresp_json(
    path: Path,
    *,
    object_id: str,
    points: np.ndarray,
    tangents: np.ndarray,
    index_pairs: np.ndarray,
    curve_ids: np.ndarray | None = None,
    associations: list[dict] | None = None,
    extra: dict | None = None,
) -> None:
    """Write 3D samples and their per-view 2D edge-point associations.

    ``index_pairs[i, v]`` is a 1-based edgel index into
    ``Edges/Edge_{v}_t1.txt``, or ``MISSING`` (-2).  Each entry of
    ``associations`` lists the matched 2D edge points ``(x, y, theta)``
    for one view, in the same 1-based point-index order.
    """
    pts = np.asarray(points, dtype=float).reshape(-1, 3)
    tng = np.asarray(tangents, dtype=float).reshape(-1, 3)
    corr = np.asarray(index_pairs, dtype=int)
    if pts.shape[0] != corr.shape[0] or tng.shape[0] != corr.shape[0]:
        raise ValueError(
            f"row mismatch: points {pts.shape[0]}, tangents {tng.shape[0]}, "
            f"index_pairs {corr.shape[0]}"
        )
    payload = {
        "object_id": str(object_id),
        "n_samples": int(pts.shape[0]),
        "n_views": int(corr.shape[1]),
        "missing": int(MISSING),
        "edgel_index_base": 1,
        "edge_point_columns": ["x", "y", "theta"],
        "points": np.asarray(pts, dtype=float).tolist(),
        "tangents": np.asarray(tng, dtype=float).tolist(),
        "index_pairs": corr.tolist(),
        "n_matched_views": (corr != MISSING).sum(axis=1).astype(int).tolist(),
        "associations": associations or [],
    }
    if curve_ids is not None:
        cids = np.asarray(curve_ids, dtype=int).reshape(-1)
        if cids.shape[0] != pts.shape[0]:
            raise ValueError(
                f"curve_ids length {cids.shape[0]} != point count {pts.shape[0]}"
            )
        payload["curve_id"] = cids.tolist()
        payload["n_curves"] = int(cids.max()) + 1 if cids.size else 0
    if extra:
        payload.update(extra)
    path = Path(path)
    with open(path, "w") as f:
        json.dump(payload, f)


def write_association_table(path: Path, associations: list[dict]) -> int:
    """Write one row per 3D–2D association: view, indices, and ``(x, y, theta)``."""
    n_rows = 0
    path = Path(path)
    with open(path, "w") as f:
        f.write("view\tpoint_index\tedgel_index\tx\ty\ttheta\n")
        for block in associations:
            view = int(block["view"])
            for i3, i2, pt in zip(
                block["point_index"], block["edgel_index"], block["edge_points"]
            ):
                f.write(
                    f"{view}\t{int(i3)}\t{int(i2)}\t"
                    f"{float(pt[0]):.8f}\t{float(pt[1]):.8f}\t{float(pt[2]):.8f}\n"
                )
                n_rows += 1
    return n_rows


def load_gt_edge_corresp_json(
    path: Path,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, dict]:
    """Load ``points``, ``tangents``, ``index_pairs``, and the full dict."""
    with open(path) as f:
        payload = json.load(f)
    points = np.asarray(payload["points"], dtype=float).reshape(-1, 3)
    tangents = np.asarray(payload["tangents"], dtype=float).reshape(-1, 3)
    corr = np.asarray(payload["index_pairs"], dtype=int)
    return points, tangents, corr, payload


def infer_image_size(object_dir: Path, n_views: int) -> tuple[int, int]:
    img_dir = Path(object_dir) / "train_img"
    for i in range(n_views):
        p = img_dir / f"{i}_colors.png"
        if p.exists():
            try:
                from PIL import Image
                with Image.open(p) as im:
                    w, h = im.size
                return int(w), int(h)
            except Exception:
                break
    return 800, 800


def count_views(object_dir: Path) -> int:
    r_path = Path(object_dir) / "RnT" / "refined_R.txt"
    if not r_path.exists():
        r_path = Path(object_dir) / "RnT" / "R_matrix.txt"
    R = np.loadtxt(r_path)
    if R.shape[0] % 3:
        raise ValueError(f"{r_path} rows ({R.shape[0]}) not a multiple of 3")
    return int(R.shape[0] // 3)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Associate ABC-NEF GT 3D curve points with 2D edge points on each image."
    )
    p.add_argument(
        "--object-dir",
        type=Path,
        required=True,
        help="ABC-NEF object folder containing Edges/, RnT/, train_img/.",
    )
    p.add_argument(
        "--gt-curves",
        type=Path,
        default=None,
        help="Optional already-sampled GT file (Nx3 xyz or Nx6 xyz+dir).  "
             "If omitted, curves are sampled from obj+feat in the unit cube.",
    )
    p.add_argument(
        "--gt-directions",
        type=Path,
        default=None,
        help="Optional Nx3 tangent file if --gt-curves is xyz-only.",
    )
    p.add_argument(
        "--dataset-root",
        type=Path,
        default=DEFAULT_DATASET_ROOT,
        help="ABC-NEF dataset root (object folders, feat/, obj/, JSON).",
    )
    p.add_argument(
        "--mesh",
        type=Path,
        default=None,
        help="Triangle mesh OBJ used for occlusion.  "
             "Default: auto-discover under --abc-nef-src/obj/<id>_*.obj",
    )
    p.add_argument(
        "--abc-nef-src",
        type=Path,
        default=None,
        help="Folder containing feat/ and obj/ (default: --dataset-root).",
    )
    p.add_argument(
        "--mesh-already-world",
        action="store_true",
        help="Mesh is already in the same world frame as the (possibly "
             "Z-flipped) GT curves; skip ABC-NEF normalize + Z-flip.",
    )
    p.add_argument(
        "--sharp-only",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Keep only feat curves with sharp=true (default: True).  "
             "Use --no-sharp-only to include every CAD curve.",
    )
    p.add_argument(
        "--sample-spacing",
        type=float,
        default=0.01,
        help="Arc-length spacing in the NEF unit cube after obj+feat "
             "normalization.  Default 0.01.",
    )
    p.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="Output directory (default: tools/GT_edge_corresp_ABC_NEF).",
    )
    p.add_argument(
        "--dist-thresh",
        type=float,
        default=1,
        help="Max pixel distance for a 3D->2D match",
    )
    p.add_argument(
        "--orient-cos-thresh",
        type=float,
        default=0.9,
        help="Min |dot| of unit 2D tangents (which is around 25.8 deg).",
    )
    p.add_argument(
        "--angle-thresh-deg",
        type=float,
        default=None,
        help="If set, overrides --orient-cos-thresh with cos(angle).",
    )
    p.add_argument(
        "--flip-z",
        choices=["auto", "on", "off"],
        default="auto",
        help="Z-flip GT (and mesh) to match refined proper rotations.",
    )
    p.add_argument(
        "--min-views",
        type=int,
        default=2,
        help="Min matched views to keep a 3D sample in the TXT export.",
    )
    p.add_argument("--no-ray-trace", action="store_true", help="Skip occlusion.")
    p.add_argument(
        "--unique-2d",
        action="store_true",
        help="Assign each 2D edge point to at most one 3D sample (greedy).  "
             "By default every 3D sample keeps its nearest consistent edge point, "
             "so neighboring samples may share one detection.",
    )
    p.add_argument(
        "--depth-tie-margin",
        type=float,
        default=0.02,
        help="When several curves fall on the same image edge, drop a curve "
             "that is farther than the closest one by more than this distance "
             "(world units).  Curves within the margin both stay.  "
             "Negative disables the tie break.",
    )
    p.add_argument(
        "--depth-tie-radius",
        type=float,
        default=2.0,
        help="Pixel radius inside which two curves' edge points are treated "
             "as the same boundary for the depth tie break.",
    )
    p.add_argument(
        "--max-views",
        type=int,
        default=-1,
        help="Debug: only process the first N views (-1 = all).",
    )
    p.add_argument("--rel-eps", type=float, default=1e-3, help="Ray self-hit relative slack.")
    p.add_argument("--abs-eps", type=float, default=1e-4, help="Ray self-hit absolute slack.")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    object_dir = args.object_dir.expanduser().resolve()
    object_id = object_dir.name
    out_dir = (args.out_dir or DEFAULT_CORRESP_DIR).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    abc_src = (args.abc_nef_src or args.dataset_root).expanduser().resolve()

    n_views = count_views(object_dir)
    if args.max_views is not None and args.max_views > 0:
        n_views_run = min(n_views, int(args.max_views))
    else:
        n_views_run = n_views

    gt_meta: dict = {}
    gt_path: Path | None = args.gt_curves
    if gt_path is not None:
        gt_path = gt_path.expanduser().resolve()
        if not gt_path.exists():
            raise SystemExit(f"GT curve file not found: {gt_path}")
        points, tangents = load_gt_curves(gt_path, args.gt_directions)
        curve_ids = curve_ids_from_gaps(points)
        gt_meta = {"source": str(gt_path), "from_cad": False}
        print(
            f"object {object_id}: {points.shape[0]} GT samples from {gt_path} "
            f"(pre-sampled; --sharp-only / --sample-spacing ignored)"
        )
    else:
        points, tangents, curve_ids, gt_meta = sample_gt_curves_from_cad(
            abc_src,
            object_id,
            sharp_only=bool(args.sharp_only),
            sample_spacing=float(args.sample_spacing),
        )
        gt_meta["from_cad"] = True
        print(
            f"object {object_id}: {points.shape[0]} GT samples from CAD "
            f"(sharp_only={args.sharp_only}, spacing={args.sample_spacing} "
            f"in unit cube, {gt_meta['n_used_curves']}/{gt_meta['n_cad_curves']} "
            f"curves, {gt_meta['n_sharp_curves']} sharp)"
        )

    points, tangents, flipped = maybe_flip_z(points, tangents, args.flip_z)
    n_pts = points.shape[0]
    print(f"Z-flip: {'yes' if flipped else 'no'} (mode={args.flip_z})")

    tag = object_id[-4:]
    gt_pts_out = out_dir / f"gt_curve_points_{tag}.txt"
    gt_dir_out = out_dir / f"gt_curve_directions_{tag}.txt"
    np.savetxt(gt_pts_out, points, delimiter=",")
    np.savetxt(gt_dir_out, tangents, delimiter=",")
    print(f"wrote {gt_pts_out} and {gt_dir_out}  (row i <-> correspondence row i)")

    K = default_intrinsics(object_dir)
    width, height = infer_image_size(object_dir, n_views)
    print(f"views: {n_views_run}/{n_views}  image: {width}x{height}")

    vertices = faces = None
    tracer = None
    do_raytrace = not args.no_ray_trace
    if do_raytrace:
        mesh_path = args.mesh
        if mesh_path is None:
            mesh_path = find_abc_obj(abc_src, object_id)
        mesh_path = Path(mesh_path).expanduser().resolve()
        vertices, faces = load_obj_mesh(mesh_path)
        if not args.mesh_already_world:
            bbox, bbox_src = load_nef_bbox(abc_src, object_id, vertices)
            # Mesh is normalized into the NEF unit cube (z > 0).  Flip it iff
            # the GT samples we will project already live in the refined-pose
            # frame (z < 0) — independent of whether *this* run applied the flip.
            mesh_flip_z = float(np.median(points[:, 2])) < 0.0
            vertices = abc_nef_normalize_vertices(
                vertices, bbox, flip_z=mesh_flip_z
            )
            print(
                f"mesh Z-flip: {'yes' if mesh_flip_z else 'no'} "
                f"(to match GT frame; bbox from {bbox_src})"
            )
        print(f"mesh: {mesh_path}  verts={len(vertices)} faces={len(faces)}")
        print("building ray tracer ...")
        tracer = MeshRayTracer(vertices, faces)
        print(f"ray tracer: {tracer.backend}")
    else:
        print("ray tracer: disabled")

    cos_thresh = float(args.orient_cos_thresh)
    if args.angle_thresh_deg is not None:
        cos_thresh = float(np.cos(np.radians(args.angle_thresh_deg)))
    print(
        f"match: dist ≤ {args.dist_thresh} px, |dot| ≥ {cos_thresh:.4f}"
        f"  unique_2d={bool(args.unique_2d)}"
        f"  depth_tie_margin={args.depth_tie_margin}"
        f"  depth_tie_radius={args.depth_tie_radius}px"
    )

    view_ids = list(range(n_views_run))
    edgels_by_view = load_edgels(object_dir, view_ids)
    poses = {v: load_Rt(object_dir, v) for v in view_ids}

    corr = np.full((n_pts, n_views), MISSING, dtype=np.int32)
    associations: list[dict] = []
    n_visible = np.zeros(n_views, dtype=int)
    n_matched = np.zeros(n_views, dtype=int)
    n_depth_dropped = np.zeros(n_views, dtype=int)

    print("associating 3D curve points with 2D edge points ...")
    for v in view_ids:
        R, t = poses[v]
        idx0, visible = construct_correspondences_one_view(
            points_3d=points,
            tangents_3d=tangents,
            K=K,
            R=R,
            t=t,
            edgels=edgels_by_view[v],
            vertices=vertices,
            faces=faces,
            dist_thresh=args.dist_thresh,
            cos_thresh=cos_thresh,
            image_size=(width, height),
            unique_2d=bool(args.unique_2d),
            do_raytrace=do_raytrace,
            rel_eps=args.rel_eps,
            abs_eps=args.abs_eps,
            tracer=tracer,
        )
        cam = camera_center_world(R, t)
        depths = np.linalg.norm(points - cam.reshape(1, 3), axis=1)
        idx0, n_drop = resolve_curve_depth_ties(
            idx0,
            curve_ids,
            depths,
            np.asarray(edgels_by_view[v], dtype=float)[:, :2],
            float(args.depth_tie_margin),
            float(args.depth_tie_radius),
        )
        n_depth_dropped[v] = n_drop
        hit = idx0 >= 0
        # Store 1-based MATLAB edgel indices.
        corr[hit, v] = idx0[hit] + 1
        hit_rows = np.flatnonzero(hit)
        if hit_rows.size:
            j = idx0[hit_rows]
            xytheta = np.asarray(edgels_by_view[v], dtype=float)[j, :3]
            associations.append({
                "view": int(v),
                "point_index": (hit_rows + 1).astype(int).tolist(),
                "edgel_index": (j + 1).astype(int).tolist(),
                "edge_points": xytheta.astype(float).tolist(),
            })
        else:
            associations.append({
                "view": int(v),
                "point_index": [],
                "edgel_index": [],
                "edge_points": [],
            })
        n_visible[v] = int(visible.sum())
        n_matched[v] = int(hit.sum())
        print(
            f"  view {v:02d}: visible {n_visible[v]:5d}/{n_pts}  "
            f"associated {n_matched[v]:5d}  depth-tie dropped {n_drop:4d}"
        )

    n_support = (corr != MISSING).sum(axis=1)
    n_keep = int((n_support >= args.min_views).sum())
    print(
        f"rows with ≥{args.min_views} views: {n_keep}/{n_pts}  "
        f"(median supports among those: "
        f"{np.median(n_support[n_support >= args.min_views]) if n_keep else 0:.0f})"
    )

    keep = n_support >= args.min_views
    txt_idx = np.flatnonzero(keep) + 1  # 1-based original 3D index
    txt = np.column_stack([txt_idx, corr[keep]])
    txt_path = out_dir / f"GT_edge_pairs_indices_{object_id[-4:]}.txt"
    np.savetxt(txt_path, txt, fmt="%d", delimiter="\t")
    print(f"wrote {txt_path}  shape={txt.shape} (filtered to ≥{args.min_views} views)")

    extra = {
        "z_flipped": bool(flipped),
        "ray_trace": bool(do_raytrace),
        "n_views_run": int(n_views_run),
        "dist_thresh_px": float(args.dist_thresh),
        "orient_cos_thresh": float(cos_thresh),
        "unique_2d": bool(args.unique_2d),
        "depth_tie_margin": float(args.depth_tie_margin),
        "depth_tie_radius_px": float(args.depth_tie_radius),
        "depth_tie_dropped_per_view": n_depth_dropped.tolist(),
        "min_views": int(args.min_views),
        "n_rows_min_views": n_keep,
        "visible_per_view": n_visible.tolist(),
        "matched_per_view": n_matched.tolist(),
        "gt_curves": str(gt_path) if gt_path is not None else None,
        "gt_points_out": str(gt_pts_out),
        "gt_directions_out": str(gt_dir_out),
        "gt_meta": gt_meta,
        "sharp_only": bool(gt_meta["sharp_only"]) if "sharp_only" in gt_meta else None,
        "sample_spacing": gt_meta.get("sample_spacing"),
        "txt_path": str(txt_path),
    }
    assoc_txt = out_dir / f"GT_3D_2D_assoc_{object_id[-4:]}.txt"
    n_assoc = write_association_table(assoc_txt, associations)
    print(f"wrote {assoc_txt}  associations={n_assoc}")

    json_path = out_dir / f"GT_3D_2D_assoc_{object_id[-4:]}.json"
    extra["assoc_txt"] = str(assoc_txt)
    extra["edge_point_columns"] = ["x", "y", "theta"]
    write_gt_edge_corresp_json(
        json_path,
        object_id=object_id,
        points=points,
        tangents=tangents,
        index_pairs=corr,
        curve_ids=curve_ids,
        associations=associations,
        extra=extra,
    )
    print(f"wrote {json_path}  (3D points + per-view 2D edge points)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
