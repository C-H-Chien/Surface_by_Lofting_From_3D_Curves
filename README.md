## Introduction
This is Brown University LEMS lab internal collaborative research project which aims to reconstruct surfaces from a set of 3D curves and multiple 2D images. Basically, it is a a hypothesis and verification framework, where many hypothesized surfaces are constructed from pairs of 3D curves, and are subsequently verified via projecting to multiview images to seek supports from detected 2D [third-order edges](https://github.com/C-H-Chien/Third-Order-Edge-Detector). This work has been proposed by the papers listed in references, but the source code is missing. Here, we *(i)* surrect its experiments, *(ii)* optimize the pipeline to make it super efficient, *(iii)* test on a modern synthetic dataset, *i.e.*, [ABC dataset](https://deep-geometry.github.io/abc-dataset/) with rendered multiviews from [NEF](https://github.com/yunfan1202/NEF_code), enabling us to easy debug the entire process, and *(iv)* test on a real data for a comparison with the results reported in the paper (see the reference below). <br />

## Toy Examples
This repo provides examples of surface reconstruction from a perfect, clean 3D curve network using the ABC-NEF dataset, and from noisy 3D curve drawings using the Amsterdam House dataset.
### Sample Data
Create a `data/` folder under the cloned repo, and create folders with dataset names containing the corresponding sample data:

- ABC-NEF: Download the [ABC-NEF sample data](https://drive.google.com/file/d/1tTkn5WciO_fgpAq6rpJTu54b0xVXu1Dn/view?usp=sharing) which contains 3D curve points, images, and  projection matrices and edges of each image from a synthetic CAD model (00000325 object).
- Amsterdam-House: Download the [Amsterdam House data](https://drive.google.com/file/d/1fZ1VYhhqDHRATmiSdunH_zQNt8D1mOqh/view?usp=sharing) with similar content as in the ABC-NEF sample data.

### Reconstruct Surface Patches
- Inside `preProcess_3D_Curves_main.m`, disable parameters `SMOOTHING`, `APPLY_LENGTH_CONSTRAINTS`, and `BREAK` for the synthetic data, since the 3D curves are perfect and thus further smoothing is unnecessary.
- Execute ``run.m`` to loft surfaces with occlusion reasoning. You might need to play with the parameters in the `occlusion_consistency_check.m` file to get better surface patches reconstruction. For ABC-NEF and Amsterdam House, set `SURFACE_FILTERING_THRESHOLD` as 200 and 500, respectively.
- The code will make a directory `tmp/filtered_surfaces` in which the final surfaces are created.

### Visualize the Surfaces through Blender
Use the Blender, and execute the script ``tools/combine.py`` which reads all the `.ply` files under `tmp/filtered_surfaces` and displays the surface reconstruction result.

## Running on Other 3D Curves
The toy examples show how surfaces can be reconstructed from a group of 3D curves. If you would like to try on your 3D curves, follow the data directory structure below under the `data/` folder (as a reference, ABC-NEF is shown in the structure here): <br />
```
data
│   
└───ABC-NEF
│   └── 00000325
│       └─── edges
│       └─── images
│       └─── projection_matrix
│   
└───<Your-data-name>
│   └── <scene-name>
│       └─── edges
│            └─── 00.mat
│            └─── 01.mat
│            └─── ...
│       └─── images
│            └─── 00.png
│            └─── 01.png
│            └─── ...
│       └─── projection_matrix
│            └─── 00.projmatrix
│            └─── 01.projmatrix
│            └─── ...
```
In each sub-folder,

- *edges*: One image corresponds to one edge file containing a Nx3 array. Each row is an edge. The first two columns are the `x` and `y` edge location, while the last column is the edge orientation in radians. You can use the third-order edge detector to create the edges from the images in the `images` folder.
- *images*: This is not mandatory if you already have the edges folder.
- *projection_matrix*: One image corresponds to one projection matrix file. The projection matrix `K[R | T]` follows the world-to-camera convention that projects 3D curve points to each 2D image.

In addition, you also need a set of 3D curves represented by a sequence of ordered 3D curve points. Generate a curve graph analogous to the `curve_graph_ABC_NEF_00000325.mat` where each cell after loading through MATLAB is a curve.

## TODOs
- [ ] Add documentation on generating surfaces from other ABC-NEF objects.
- [ ] Reorganize the code so no intermediate files are generated and gather all settings in a file
- [ ] Document all the parameters.
- [ ] Remove redundant, unnecessary scripts and code since they may not be in use and are confusing.
- [ ] Create a python version for the benefit of the research community
- [ ] Consolidate overlapping surfaces with similar Gaussian curvature

## Contributors
- Zichang Gao (zichang_gao@brown.edu)
- Sanithu Heengama (sanithu_heengama@brown.edu)
- Chiang-Heng Chien (chiang-heng_chien@brown.edu)
- *Advisory Board:*
Prof. Benjamin Kimia (benjamin_kimia@brown.edu) and Prof. Ricardo Fabbri (rfabbri@iprj.uerj.br)

## References
The surface patch reconstruction through lofting was originated from the following paper. Unfortunately there is no publicly available code.
```BibTeX
@InProceedings{Usumezbas:Fabbri:Kimia:CVPR:2017,
  title={The surfacing of multiview 3D drawings via lofting and occlusion reasoning},
  author={Usumezbas, Anil and Fabbri, Ricardo and Kimia, Benjamin B},
  booktitle={Proceedings of the IEEE Conference on Computer Vision and Pattern Recognition},
  pages={2980--2989},
  year={2017}
}
```
Rather than using the ground-truth 3D curves from the ABC-NEF dataset, 3D Curvix is a good source to try on generating 3D curves from multiple images with association between 2D edges and 3D curve points. See the paper below and [the code](https://github.com/C-H-Chien/3D_Curvix) for more details.
```BibTeX
@InProceedings{Zhang:Chien:Fabbri:Kimia:BMVC:2025,
  title={{3D Curvix: From Multiview 2D Edges to 3D Curve Segments}},
  author={Zhang, Qiwu and Chien, Chiang-Heng and Fabbri, Ricardo and Kimia, Benjamin},
  booktitle = {Proceedings of the British Machine Vision Conference (BMVC)},
  year={2025}
}
```

## Lisence
The code in this repository is under the lisence GNU GPLv3. <br />
Please open an issue if you have any questions. Improving the code through opening a PR is also encouraged.
