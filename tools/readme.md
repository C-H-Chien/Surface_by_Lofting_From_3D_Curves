# Tools

## combine.py

This one is used to import all the surfaces to blender. Copy this script to blender, and replace the directory with the folder storing all the output surfaces. After running, you may use blender' s join function to combine all surfaces.

## curve_sampling

This one is used to sample ABC-NEF dataset's parametrized curve representation to 3D curve points. Set the paths of your local machine in the ``main.m`` file as well as the object of the ABC-NEF dataset. Execute ``main.m`` and you will get the 3D ground-truth curve points. Note that this requires **.yml** file of the object which can be accessed from the ABC-NEF dataset. It is optional to write the 3D curve points as a ``.mat`` file which can be used by the ``projection/projection.m`` code.

## projection

This one is used to convert camera matrices in the ABC CAD object dataset to the coordinates we use.

## Use ABC dataset as input

[April-20-2025 Update] Extracting ground-truth curve points from the ABC-NEF dataset has been isolated from the NEF_code official github repo. Run ``get_ABC_NEF_gt_curve_points.py`` and the outputs of the ground-truth curves as well as all the curve points will reside under ``gt_curve_points`` folder. You can generate the ground-truth curve points of only one object speficied by its object name (_e.g._, 00000006) [here](https://github.com/C-H-Chien/Surface_by_Lofting_From_3D_Curves/blob/main/tools/get_ABC_NEF_gt_curve_points.py#L103), or set ``do_only_on_desired_obj`` [here](https://github.com/C-H-Chien/Surface_by_Lofting_From_3D_Curves/blob/main/tools/get_ABC_NEF_gt_curve_points.py#L104) as ``false`` to generate ground-truth curve points of _all_ objects. <br />
Note that before running ``get_ABC_NEF_gt_curve_points.py`` code, make sure to download the `.obj` files of the ABC-NEF dataset at this [Google Drive](https://drive.google.com/file/d/1DmDi0QdfwZodXWXA-Nv8WRfTlBnIPsMO/view?usp=share_link).

ABC dataset example download

```shell
wget https://archive.nyu.edu/rest/bitstreams/89087/retrieve abc_0000_feat_v00.7z
```

Download multiview images

```
https://github.com/yunfan1202/NEF_code
```

Run ``curve_sampling/main.m`` to get 3d curve points

Run ``projection`` to get converted camera matrix (NEF paper processed multiview images' camera matrix as input)

Run  ``third_order_edge_dector`` to get the edges of each view (NEF paper processed multiview images as input)

Run lofting pipeline, curve smoothing and breaking would be unnecessary.

Run ``conbine.py`` in blender

