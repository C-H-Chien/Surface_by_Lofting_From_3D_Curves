## Introduction
This is Brown University LEMS lab internal collaborative research project which aims to reconstruct surfaces from a set of 3D curves and multiple 2D images. Basically, it is a a hypothesis and verification framework, where many hypothesized surfaces are constructed from pairs of 3D curves, and are subsequently verified via projecting to multiview images to seek supports from detected 2D [third-order edges](https://github.com/C-H-Chien/Third-Order-Edge-Detector). This work has been proposed by the papers listed in references, but the source code is missing. Here, we *(i)* surrect its experiments, *(ii)* optimize the pipeline to make it super efficient, and *(iii)* run on a modern synthetic dataset, *i.e.*, [ABC dataset](https://deep-geometry.github.io/abc-dataset/) with rendered multiviews from [NEF](https://github.com/yunfan1202/NEF_code), enabling us to easy debug the entire process. <br />

## How to run
- Download [sample data](https://drive.google.com/file/d/1gYFKFiUe2GCFWLKpOgJ_s1Fn8xTjoQqE/view?usp=drive_link) or use another input, including 3d curves, 2d edges, images and projection matrices, and modify input path in ``preProcess_3D_Curves_main`` and ``occlusion_consistency_check``.
- Run ``run.m``
- Use Blender with ``combine.py`` to check the output

## Contributors
Zichang Gao (zichang_gao@brown.edu) <br />
Chiang-Heng Chien (chiang-heng_chien@brown.edu)

## References
``Usumezbas, Anil, Ricardo Fabbri, and Benjamin B. Kimia. "From multiview image curves to 3D drawings." In Computer Vision–ECCV 2016: 14th European Conference, Amsterdam, The Netherlands, October 11–14, 2016, Proceedings, Part IV 14, pp. 70-87. Springer International Publishing, 2016.`` ([Paper Link](https://link.springer.com/chapter/10.1007/978-3-319-46493-0_5)) <br />
``Usumezbas, Anil, Ricardo Fabbri, and Benjamin B. Kimia. "The surfacing of multiview 3d drawings via lofting and occlusion reasoning." In Proceedings of the IEEE Conference on Computer Vision and Pattern Recognition, pp. 2980-2989. 2017.`` ([Paper Link](https://openaccess.thecvf.com/content_cvpr_2017/html/Usumezbas_The_Surfacing_of_CVPR_2017_paper.html))

## Lisence
The code in this repository is under the lisence GNU GPLv3. <br />
Please contact the authors if you have any questions.
