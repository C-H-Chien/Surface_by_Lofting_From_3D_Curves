import os
import bpy
from pathlib import Path

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

bpy.ops.outliner.orphans_purge()
bpy.ops.outliner.orphans_purge()
bpy.ops.outliner.orphans_purge()
    
surfaceDir = "<replace with the directory of surfaces>"
files = os.listdir(surfaceDir)
for f in files:
    fname = surfaceDir + f
    bpy.ops.import_mesh.ply(filepath=fname)
    print(fname)
