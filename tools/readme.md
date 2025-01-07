# Tools

## combine.py

This one is used to import all the surfaces to blender. Copy this script to blender, and replace the directory with the folder storing all the output surfaces. After running, you may use blender' s join function to combine all surfaces.

## curve_sampling

This one is used to sample ABC-NEF dataset's parametrized curve representation to 3D curve points. Set the paths of your local machine in the ``main.m`` file as well as the object of the ABC-NEF dataset. Execute ``main.m`` and you will get the 3D ground-truth curve points. Note that this requires **.yml** file of the object which can be accessed from the ABC-NEF dataset. It is optional to write the 3D curve points as a ``.mat`` file which can be used by the ``projection/projection.m`` code.

## projection

This one is used to convert camera matrices in the ABC CAD object dataset to the coordinates we use.

## Use ABC dataset as input

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

