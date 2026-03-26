import os
import bpy
from pathlib import Path

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

bpy.ops.outliner.orphans_purge()
bpy.ops.outliner.orphans_purge()
bpy.ops.outliner.orphans_purge()

print(f"Try: {bpy.context.space_data.text.filepath}")

current_file_path = bpy.context.space_data.text.filepath
directory = os.path.dirname(current_file_path)
surface_dir = os.path.join(directory, "../tmp/filtered_surfaces/")
print(f"Directory: {directory}")
print(f"Path: {surface_dir}")





#surfaceDir = filepath + "/home/chchien/BrownU/research/SurfacingByLofting/GitHub/Surface_by_Lofting_From_3D_Curves/blender/output/"
files = os.listdir(surface_dir)
for f in files:
    fname = surface_dir + f
    #print(fname)
    if bpy.app.version >= (4, 0, 0):
    	bpy.ops.wm.ply_import(filepath=fname)
    else:
    	bpy.ops.import_mesh.ply(filepath=fname)
    print(fname)
