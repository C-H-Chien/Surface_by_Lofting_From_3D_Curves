# GT 3D curve point to 2D edge point association

`GT_edge_corresp_construction.py` associates each ground-truth 3D curve sample with the detected 2D edge point on every image of one ABC-NEF object. Each 3D sample carries a unit tangent, and each 2D edge point is `(x, y, theta)`. For each camera the code _(i)_ samples oriented 3D curve points in the NEF unit cube, _(ii)_ z-flips them to match the refined poses, _(iii)_ ray-traces the camera-to-point ray against the object mesh, _(iv)_ projects visible points and tangents into the image, and _(v)_ keeps the 2D edge point whose location and orientation both agree with that projection.

## How to run the code

The code relies on commonly used python packages, with optional dependency on `trimesh` and `embreex` for faster ray tracing. 

Specifiying the ABC-NEF object directory and the output data directory is required to run the code.
```bash
python tools/GT_edge_corresp_construction.py \
  --object-dir /path/to/ABC-NEF/object/folder/ \
  --out-dir tools/GT_edge_corresp_ABC_NEF/
```

## Dataset layout
```
ABC-NEF/
  chunk_0000_feats.json      # CAD curves (vert_indices, sharp, …) for 387 IDs
  chunk_0000_stats.json      # bbox used to map raw ABC → unit cube
  feat/                      # per-object YAML (fallback if JSON is missing)
  obj/                       # triangle meshes for sampling + occlusion
  00000006/                  # one rendered object (113 of these from the standard ABC-NEF dataset)
    Edges/Edge_{v}_t1.txt    # TO-edgels: x, y, theta
    RnT/refined_R.txt
    RnT/refined_T.txt
    train_img/{v}_colors.png
```

## Outputs

`--out-dir` defaults to `tools/GT_edge_corresp_ABC_NEF/`, and the file name with a tag from the last four digits of
the ABC-NEF object id, _e.g._, `00000006` -> `0006`.

| File | Contents |
|---|-----|
| `GT_3D_2D_assoc_{tag}.json` | Primary output. 3D `points`, `tangents`, `curve_id` (one integer per sample), `index_pairs` (`N×V`, 1-based edgel indices, `-2` = missing), and `associations`: for each view, the matched 2D edge points `(x, y, theta)` with their 1-based 3D and edgel indices. |
| `GT_3D_2D_assoc_{tag}.txt` | One association per row: `view`, `point_index`, `edgel_index`, `x`, `y`, `theta`. |
| `GT_edge_pairs_indices_{tag}.txt` | Tab-separated. First column = 1-based 3D index; remaining columns = per-view edgel indices. Only rows with \(\ge\) `--min-views` matches (default 2). |
| `gt_curve_points_{tag}.txt` | `(N, 3)` comma-separated XYZ (same frame as the JSON). |
| `gt_curve_directions_{tag}.txt` | `(N, 3)` unit tangents, same row order. |

Load the JSON in Python:

```python
import json, numpy as np
d = json.load(open("tools/GT_edge_corresp_ABC_NEF/GT_3D_2D_assoc_0006.json"))
points = np.asarray(d["points"])          # (N, 3)
tangents = np.asarray(d["tangents"])      # (N, 3)
curve_id = np.asarray(d["curve_id"])      # (N,)  which GT curve
corr = np.asarray(d["index_pairs"])       # (N, V)  1-based, -2 missing
view0 = d["associations"][0]
xytheta = np.asarray(view0["edge_points"])  # (M, 3) x, y, theta
```

## Visualization

`visualize_GT_3D_2D_assoc.py` paints each GT curve with its own color and draws the associated 2D edge points on every image in that same color.

```bash
python tools/visualize_GT_3D_2D_assoc.py \
  --assoc tools/GT_edge_corresp_ABC_NEF/GT_3D_2D_assoc_0006.json \
  --object-dir /media/chchien/843557f5-9293-49aa-8fb8-c1fc6c72f7ea/home/chchien/datasets/ABC-NEF/00000006
```

Figures land in `tools/GT_edge_corresp_ABC_NEF/vis_0006/`: `gt_curves_3d.png`, one `views/view_XX.png` per camera, and `views_montage.png`.

## Sampling 3D GT

3D samples always come from the original ABC-NEF ``.obj`` mesh and feature curves (`chunk_0000_feats.json`, or `feat/*.yml` if the JSON is missing):

1. Map raw ABC vertices into the NEF unit cube with the stats bbox.
2. Walk each feature polyline (`vert_indices`) and sample at `--sample-spacing` (default `0.01` in the cube).
3. Keep only `sharp: true` curves unless `--no-sharp-only`.

Unit-cube coordinates are required so points agree with the cameras and
mesh. Spacing in the cube (not in raw ABC) keeps density comparable across
objects of different CAD size.

`--gt-curves FILE` is an optional override that loads an already-sampled
`Nx3` / `Nx6` cloud (`--sharp-only` / `--sample-spacing` ignored).

## Coordinates

ABC-NEF rendering puts the object in a unit cube: longest bbox side scaled to
1, then shifted so the box is centered at \((0.5, 0.5, 0.5)\). After that,
samples have positive \(z\).

Original ABC-NEF rotations are improper (\(\det R = -1\)). `refined_R.txt`
converts them by right-multiplying \(\mathrm{diag}(1,1,-1)\), so GT and the
mesh must be Z-flipped before projection. `--flip-z auto` (default) flips
when the cloud’s median \(z\) is positive.

## Matching and occlusion

A projected 3D sample matches a 2D edgel if:

- pixel distance \(\le\) `--dist-thresh` (default `0.6`), and
- \(\lvert \dot{}\rvert\) of unit 2D tangents \(\ge\) `--orient-cos-thresh`
  (default `0.9`, about \(25.8^\circ\)). Edgel files store theta in
  column 2, not a unit vector.

Samples of one curve may share a 2D edge point.  When another curve's edge point lies within `--depth-tie-radius` pixels (default `2`), the farther curve is dropped if it is more than `--depth-tie-margin` behind the closer one (default `0.02` in the unit cube).  Curves at the same depth, such as a corner, both stay.  Pass `--depth-tie-margin -1` to keep every curve.  `--unique-2d` is a separate greedy rule that gives each edge point to only one 3D sample.

Ray tracing hides samples whose ray hits the mesh before the curve. Curve
samples lie *on* the surface, so a small distance slack
(`--rel-eps`, `--abs-eps`) avoids treating the surface itself as an occluder.
Without `trimesh`/`embreex`, a uniform-grid Möller–Trumbore tracer is used
(~2 s/view on `00000006`). Skip occlusion with `--no-ray-trace`.



## Common commands

Write to `tools/GT_edge_corresp_ABC_NEF/` (default `--out-dir`):

```bash
python tools/GT_edge_corresp_construction.py \
  --object-dir /media/chchien/843557f5-9293-49aa-8fb8-c1fc6c72f7ea/home/chchien/datasets/ABC-NEF/00000006
```

All CAD curves, denser samples, no occlusion (debug):

```bash
python tools/GT_edge_corresp_construction.py \
  --object-dir /media/chchien/843557f5-9293-49aa-8fb8-c1fc6c72f7ea/home/chchien/datasets/ABC-NEF/00000006 \
  --out-dir data/ \
  --no-sharp-only \
  --sample-spacing 0.005 \
  --no-ray-trace \
  --max-views 2
```



## CLI reference

| Flag | Default | Role |
|---|---|---|
| `--object-dir` | required | Folder with `Edges/`, `RnT/`, `train_img/` |
| `--out-dir` | `tools/GT_edge_corresp_ABC_NEF/` | Where outputs are written |
| `--dataset-root` | `/media/chchien/843557f5-9293-49aa-8fb8-c1fc6c72f7ea/home/chchien/datasets/ABC-NEF` | `feat/`, `obj/`, JSON |
| `--abc-nef-src` | `--dataset-root` | Override folder that contains `feat/` and `obj/` |
| `--gt-curves` / `--gt-directions` | unset | Optional already-sampled 3D GT (skip obj sampling) |
| `--sharp-only` / `--no-sharp-only` | sharp-only | CAD curves only |
| `--sample-spacing` | `0.01` | Arc length in the unit cube |
| `--mesh` | auto `obj/<id>_*.obj` | Occlusion mesh |
| `--mesh-already-world` | off | Skip NEF normalize + Z-flip on the mesh |
| `--flip-z` | `auto` | `auto` / `on` / `off` |
| `--dist-thresh` | `0.6` | Max match distance (pixels) |
| `--orient-cos-thresh` | `0.9` | Min \(\lvert\dot{}\rvert\) of 2D tangents |
| `--angle-thresh-deg` | unset | Overrides the cosine threshold |
| `--min-views` | `2` | Filter for the TXT export only |
| `--no-ray-trace` | off | Skip occlusion |
| `--unique-2d` | off | One 2D edge point per 3D sample at most |
| `--depth-tie-margin` | `0.02` | Drop a farther curve on the same image edge. Negative disables it |
| `--depth-tie-radius` | `2` | Pixel radius for that depth comparison |
| `--max-views` | all | Debug: first \(N\) views |
| `--rel-eps` / `--abs-eps` | `1e-3` / `1e-4` | Ray self-hit slack |

```bash
python tools/GT_edge_corresp_construction.py --help
```
