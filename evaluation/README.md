# Evaluation of Surface Patch Reconstruction

The script loads all filtered reconstruction PLYs from a directory (default: `tmp/filtered_surfaces`), concatenates them into one mesh, aligns coordinates with the GT into a shared unit box, then reports precision rate, recall rate, and F1-score.

## Requirements

```bash
pip install numpy scipy trimesh
```

For interactive mesh visualization (which is optional), additionally install `pyglet` but ensure that its version is lower,
```bash
pip install "pyglet<2"
```
Without pyglet, visualization falls back to a matplotlib point-cloud plot.

## Inputs

| Input | Description |
|-------|-------------|
| `--gt-file` | Path to the ground-truth mesh (e.g. ABC-NEF `.obj`) which can be downloaded from the original ABC-NEF dataset |
| `--filtered-dir` | Directory of reconstructed `.ply` surfaces (default: `tmp/filtered_surfaces`) |

Reconstruction PLYs are produced by the main pipeline and copied into `tmp/filtered_surfaces` after occlusion filtering.

## Usage

Run from the repository root:

```bash
# Area-based evaluation (default mode)
python3 evaluation/eval_surfaces_main.py \
  --mode area \
  --gt-file /path/to/gt.obj

# Point-based evaluation
python3 evaluation/eval_surfaces_main.py \
  --mode point \
  --gt-file /path/to/gt.obj \
  --num-points 100000

# Custom reconstruction directory and threshold
python3 evaluation/eval_surfaces_main.py \
  --mode area \
  --gt-file /path/to/gt.obj \
  --filtered-dir tmp/filtered_surfaces \
  --tau 0.02

# Visualize normalized GT (green) and reconstruction (red)
python3 evaluation/eval_surfaces_main.py \
  --mode point \
  --gt-file /path/to/gt.obj \
  --visualize-normalized
```

### Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `--mode` | `area` | `area` or `point` |
| `--gt-file` | *(required)* | Ground-truth mesh path |
| `--filtered-dir` | `tmp/filtered_surfaces` | Directory of reconstructed PLYs |
| `--tau` | `0.02` | Distance threshold in the normalized unit-cube coordinate |
| `--num-points` | `100000` | Samples per surface for point-based mode |
| `--visualize-normalized` | off | Show GT and reconstruction after alignment |

## Coordinate alignment

ABC-NEF ground-truth OBJs are typically in raw coordinates, _e.g._, `[0, 100]^3`, while reconstructed PLYs from this pipeline already live in the ABC-NEF unit box (`[0, 1]^3`, centered at `0.5`). Thus, `normalize_to_unit_box` maps the GT with the unit cube. By default the reconstruction remains at its coordinate. When it appears to share the GT’s raw scale, that same affine transform is applied. This normalized coordinate is where all distances (`tau`) are measured.

## How evaluation works

A point / surface patch counts as a match if its distance to the other surface is less than `tau`. Based on this criteria, three evaluation metrics are reported at the end.
- Precision: how much of the reconstruction is close to the GT
- Recall: how much of the GT is covered by the reconstruction
- F1: harmonic mean of precision and recall

### Area-based (`--mode area`) (Still under development)

Measures matched surface area rather than discrete samples. For coverage of `source` by `target`:
1. Subdivide `source` until every edge is shorter than `tau / 2`.
2. Take each dense triangle’s centroid and area.
3. Find the nearest point on `target` for each centroid.
4. If distance `< tau`, count that triangle’s area as matched.
5. Return `matched_area / total_area × 100`.

Precision is thus the area coverage of reconstruction with respect to the GT surface area, while the recall is the area coverage of GT with respect to the reconstruction.

Note that this evaluation is typically very slow, but weights by actual area, which helps when triangle sizes are uneven.

### Point-based (`--mode point`)

1. Sample `num_points` points uniformly from the GT and from the concatenated reconstruction.
2. Build a KD-tree on each cloud.
3. Precision = fraction of reconstruction points within `tau` of the GT.
4. Recall = fraction of GT points within `tau` of the reconstruction.

