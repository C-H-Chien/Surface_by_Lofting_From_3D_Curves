import argparse
import glob
import os
import numpy as np
import trimesh
from scipy.spatial import cKDTree


def normalize_to_unit_box(gt_mesh, rec_mesh=None):
    """
    Map the ground-truth mesh into the ABC-NEF unit box ([0, 1]^3 centered
    at 0.5), matching tools/get_ABC_NEF_gt_curve_points.py:

        ((v - bbox_center) / max_extent) + 0.5

    Reconstructed PLYs from this pipeline are already in that frame. Applying
    the GT's raw-coordinate transform to them collapses them near the origin,
    so the same affine map is applied to rec_mesh only when it appears to
    share the GT's raw coordinate scale.
    """
    min_bounds = gt_mesh.bounds[0]
    max_bounds = gt_mesh.bounds[1]
    extents = max_bounds - min_bounds
    center = (max_bounds + min_bounds) / 2.0
    scale = np.max(extents)

    if scale == 0:
        raise ValueError("Ground truth mesh has zero size in all dimensions.")

    gt_mesh.vertices = ((gt_mesh.vertices - center) / scale) + 0.5

    if rec_mesh is not None:
        rec_extent = float(np.max(rec_mesh.extents))
        # Same raw frame as GT if rec extent is comparable to GT's pre-normalization extent.
        shares_raw_frame = rec_extent > 0 and (scale / rec_extent) < 2.0
        if shares_raw_frame:
            rec_mesh.vertices = ((rec_mesh.vertices - center) / scale) + 0.5
        return gt_mesh, rec_mesh

    return gt_mesh


def concatenate_meshes(meshes):
    """Concatenate multiple Trimesh objects into one mesh."""
    if len(meshes) == 0:
        raise ValueError("No meshes provided for concatenation.")
    if len(meshes) == 1:
        return meshes[0]
    return trimesh.util.concatenate(meshes)


def calculate_area_coverage(source_mesh, target_mesh, tau):
    """
    Calculates what percentage of the source_mesh's surface area
    lies within distance tau of the target_mesh's continuous surface.
    """
    max_edge_length = tau / 2.0
    v_dense, f_dense = trimesh.remesh.subdivide_to_size(
        source_mesh.vertices,
        source_mesh.faces,
        max_edge=max_edge_length
    )
    dense_source = trimesh.Trimesh(vertices=v_dense, faces=f_dense)
    centroids = dense_source.triangles_center
    face_areas = dense_source.area_faces
    _, distances, _ = target_mesh.nearest.on_surface(centroids)
    valid_mask = distances < tau
    matched_area = np.sum(face_areas[valid_mask])
    total_area = np.sum(face_areas)

    if total_area == 0:
        return 0.0

    return (matched_area / total_area) * 100.0


def eval_reconstruction_area_based(gt_mesh_path, rec_mesh, tau=0.01):
    """
    Computes area-based precision/recall/F1 between a GT mesh and a
    reconstructed mesh.
    """
    gt_mesh = trimesh.load(gt_mesh_path, force='mesh')
    if gt_mesh.is_empty:
        raise ValueError(f"Ground truth mesh is empty: {gt_mesh_path}")
    if rec_mesh.is_empty:
        raise ValueError("Reconstructed mesh is empty.")

    gt_mesh, rec_mesh = normalize_to_unit_box(gt_mesh, rec_mesh)
    precision = calculate_area_coverage(source_mesh=rec_mesh, target_mesh=gt_mesh, tau=tau)
    recall = calculate_area_coverage(source_mesh=gt_mesh, target_mesh=rec_mesh, tau=tau)

    if precision + recall == 0:
        f1_score = 0.0
    else:
        f1_score = 2 * (precision * recall) / (precision + recall)

    return precision, recall, f1_score


def generate_point_cloud(mesh_data, num_points=100000):
    """
    Uniformly samples a dense point cloud from a mesh.

    Parameters:
        mesh_data: Can be a file path string (e.g., 'model.obj') or a dictionary
                   containing 'vertices' (N, 3) and 'faces' (M, 3) numpy arrays.
        num_points: Number of points to sample across the surface area.

    Returns:
        numpy.ndarray: An (N, 3) array of sampled points.
    """
    if isinstance(mesh_data, str):
        mesh = trimesh.load(mesh_data, force='mesh')
    elif isinstance(mesh_data, dict):
        mesh = trimesh.Trimesh(
            vertices=mesh_data['vertices'],
            faces=mesh_data['faces']
        )
    else:
        raise ValueError("mesh_data must be a filepath string or a dict with vertices/faces.")

    points, _ = trimesh.sample.sample_surface(mesh, num_points)
    return points


def sample_surface_points(mesh, num_points=100000):
    """Sample points uniformly from a mesh surface."""
    if mesh.is_empty:
        return np.zeros((0, 3), dtype=float)
    points, _ = trimesh.sample.sample_surface(mesh, num_points)
    return points


def evaluate_reconstruction(gt_points, rec_points, threshold):
    """
    Calculates Precision, Recall, and F1-score between two point clouds.

    Parameters:
        gt_points: (N, 3) numpy array of Ground Truth points.
        rec_points: (M, 3) numpy array of Reconstructed points.
        threshold: The distance threshold (tau) for a point to be considered a match.

    Returns:
        tuple: (precision, recall, f1_score) as percentages.
    """
    gt_tree = cKDTree(gt_points)
    rec_tree = cKDTree(rec_points)
    dist_to_gt, _ = gt_tree.query(rec_points)
    precision = np.mean(dist_to_gt < threshold) * 100.0
    dist_to_rec, _ = rec_tree.query(gt_points)
    recall = np.mean(dist_to_rec < threshold) * 100.0

    if precision + recall == 0:
        f1_score = 0.0
    else:
        f1_score = 2 * (precision * recall) / (precision + recall)

    return precision, recall, f1_score


def visualize_point_cloud(points, title="Ground Truth Point Cloud", sample_limit=5000):
    """
    Visualize a 3D point cloud.

    Tries trimesh viewer first, then falls back to matplotlib if unavailable.
    """
    try:
        cloud = trimesh.points.PointCloud(points)
        scene = cloud.scene()
        scene.show(title=title)
        return
    except Exception as exc:
        print(f"Trimesh viewer unavailable, falling back to matplotlib: {exc}")

    try:
        import matplotlib.pyplot as plt
        from mpl_toolkits.mplot3d import Axes3D  # noqa: F401

        if len(points) > sample_limit:
            idx = np.random.choice(len(points), sample_limit, replace=False)
            points_to_plot = points[idx]
        else:
            points_to_plot = points

        fig = plt.figure(figsize=(8, 8))
        ax = fig.add_subplot(111, projection='3d')
        ax.scatter(points_to_plot[:, 0], points_to_plot[:, 1], points_to_plot[:, 2], s=1, color='blue', alpha=0.6)
        ax.set_title(title)
        ax.set_xlabel('X')
        ax.set_ylabel('Y')
        ax.set_zlabel('Z')
        plt.show()
    except ImportError:
        print("Unable to visualize point cloud: matplotlib is not installed.")


def visualize_meshes(gt_mesh, rec_mesh, title="Normalized GT and Reconstruction", sample_limit=5000):
    """Visualize two meshes together; falls back to point cloud sampling if trimesh mesh viewer is not available"""
    try:
        gt_vis = gt_mesh.copy()
        rec_vis = rec_mesh.copy()
        gt_vis.visual.vertex_colors = [0, 255, 0, 100]
        rec_vis.visual.vertex_colors = [255, 0, 0, 100]
        scene = trimesh.Scene([gt_vis, rec_vis])
        scene.show(title=title)
        return
    except Exception as exc:
        print(f"Trimesh mesh viewer unavailable, falling back to point cloud visualization: {exc}")

    try:
        import matplotlib.pyplot as plt
        from mpl_toolkits.mplot3d import Axes3D  # noqa: F401

        gt_points = sample_surface_points(gt_mesh, sample_limit)
        rec_points = sample_surface_points(rec_mesh, sample_limit)

        fig = plt.figure(figsize=(10, 8))
        ax = fig.add_subplot(111, projection='3d')
        ax.scatter(gt_points[:, 0], gt_points[:, 1], gt_points[:, 2], s=1, color='green', alpha=0.4, label='GT')
        ax.scatter(rec_points[:, 0], rec_points[:, 1], rec_points[:, 2], s=1, color='red', alpha=0.4, label='Reconstruction')
        ax.set_title(title)
        ax.set_xlabel('X')
        ax.set_ylabel('Y')
        ax.set_zlabel('Z')
        ax.legend()
        plt.show()
    except ImportError:
        print("Unable to visualize meshes: matplotlib is not installed.")


def load_filtered_reconstructed_points(filtered_dir, total_samples=100000):
    """Load points sampled from all filtered reconstructed PLY surfaces."""
    ply_files = sorted(glob.glob(os.path.join(filtered_dir, '*.ply')))
    if len(ply_files) == 0:
        raise FileNotFoundError(f'No filtered PLY files found in {filtered_dir}')

    samples_per_mesh = max(1000, total_samples // len(ply_files))
    samples_per_mesh = min(samples_per_mesh, 5000)
    sampled_points = []

    for ply_path in ply_files:
        mesh = trimesh.load(ply_path, force='mesh')
        if mesh.is_empty:
            continue

        pts, _ = trimesh.sample.sample_surface(mesh, samples_per_mesh)
        sampled_points.append(pts)

    if len(sampled_points) == 0:
        raise ValueError(f'No valid reconstructed meshes found in {filtered_dir}')

    reconstructed_points = np.vstack(sampled_points)
    if reconstructed_points.shape[0] > total_samples:
        idx = np.random.choice(reconstructed_points.shape[0], total_samples, replace=False)
        reconstructed_points = reconstructed_points[idx]

    return reconstructed_points


def load_reconstructed_meshes(filtered_dir):
    """Load all reconstructed meshes from a directory of PLY files."""
    ply_files = sorted(glob.glob(os.path.join(filtered_dir, '*.ply')))
    if len(ply_files) == 0:
        raise FileNotFoundError(f'No filtered PLY files found in {filtered_dir}')

    meshes = []
    for ply_path in ply_files:
        mesh = trimesh.load(ply_path, force='mesh')
        if mesh.is_empty:
            continue
        meshes.append(mesh)

    if len(meshes) == 0:
        raise ValueError(f'No valid reconstructed meshes found in {filtered_dir}')

    return meshes


def eval_reconstruction_point_based(gt_mesh_path, rec_mesh_paths, tau=0.01, num_points=100000):
    """Evaluate precision/recall/F1 using point clouds sampled from meshes."""
    gt_mesh = trimesh.load(gt_mesh_path, force='mesh')
    if gt_mesh.is_empty:
        raise ValueError(f"Ground truth mesh is empty: {gt_mesh_path}")

    rec_meshes = []
    for path in rec_mesh_paths:
        mesh = trimesh.load(path, force='mesh')
        if mesh.is_empty:
            continue
        rec_meshes.append(mesh)

    if len(rec_meshes) == 0:
        raise ValueError(f"No valid reconstructed meshes found in {os.path.dirname(rec_mesh_paths[0])}")

    rec_mesh = concatenate_meshes(rec_meshes)
    gt_mesh, rec_mesh = normalize_to_unit_box(gt_mesh, rec_mesh)
    gt_points = sample_surface_points(gt_mesh, num_points)
    rec_points = sample_surface_points(rec_mesh, num_points)

    return evaluate_reconstruction(gt_points, rec_points, tau)


def parse_arguments():
    parser = argparse.ArgumentParser(description="Evaluate 3D reconstruction using point-based or area coverage metrics.")
    parser.add_argument('--mode', choices=['point', 'area'], default='area',
                        help='Evaluation mode to use: "point" for point-cloud comparison, "area" for mesh area coverage.')
    parser.add_argument('--gt-file', required=True,
                        help='Path to the ground truth mesh file.')
    parser.add_argument('--filtered-dir', default=os.path.join(os.getcwd(), 'tmp', 'filtered_surfaces'),
                        help='Directory containing reconstructed PLY meshes.')
    parser.add_argument('--tau', type=float, default=0.02,
                        help='Distance threshold for matching in normalized coordinates.')
    parser.add_argument('--num-points', type=int, default=100000,
                        help='Number of points to sample per surface for point-based evaluation.')
    parser.add_argument('--visualize-normalized', action='store_true',
                        help='Visualize normalized ground truth and reconstructed meshes together.')
    return parser.parse_args()

if __name__ == "__main__":
    args = parse_arguments()
    ply_files = sorted(glob.glob(os.path.join(args.filtered_dir, '*.ply')))
    if len(ply_files) == 0:
        raise FileNotFoundError(f'No filtered PLY files found in {args.filtered_dir}')

    if args.visualize_normalized:
        gt_mesh = trimesh.load(args.gt_file, force='mesh')
        if gt_mesh.is_empty:
            raise ValueError(f"Ground truth mesh is empty: {args.gt_file}")
        rec_meshes = load_reconstructed_meshes(args.filtered_dir)
        rec_mesh = concatenate_meshes(rec_meshes)
        gt_mesh, rec_mesh = normalize_to_unit_box(gt_mesh, rec_mesh)
        visualize_meshes(gt_mesh, rec_mesh, title='Normalized GT and Reconstruction')

    if args.mode == 'area':
        rec_meshes = load_reconstructed_meshes(args.filtered_dir)
        rec_mesh = concatenate_meshes(rec_meshes)
        precision, recall, f1 = eval_reconstruction_area_based(
            gt_mesh_path=args.gt_file,
            rec_mesh=rec_mesh,
            tau=args.tau
        )
        mode_label = 'Area coverage'
    else:
        precision, recall, f1 = eval_reconstruction_point_based(
            gt_mesh_path=args.gt_file,
            rec_mesh_paths=ply_files,
            tau=args.tau,
            num_points=args.num_points
        )
        mode_label = 'Point-based'

    print("--- 3D Reconstruction Evaluation Results ---")
    print(f"Mode:            {mode_label}")
    print(f"Threshold (tau): {args.tau}")
    print(f"Precision:       {precision:.2f}%")
    print(f"Recall:          {recall:.2f}%")
    print(f"F1-Score:        {f1:.2f}%")
