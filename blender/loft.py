# Loft curves given by files into surface
#
# INPUT 
#    p0.txt, p1.txt, p2.txt, ... 
#       An arbitrary number of curves to be lofted. Each p*.txt is one curve defined by
#       a sequence of X Y Z point samples arranged in an nx3 array, space separated.
#
# OUTPUT
#    loftsurf.ply
#
# USAGE
#
#   Commandline through a shell wrapper 'bloft'
#      bloft   # it will read as many curves as you have, one fragment per .txt
#
#   Running directly
#      blender -b -nosound -P blender_loft.py
#       
#   Running inside blender console (to debug)
#      filename = "PWD/blender_loft.py"
#      exec(compile(open(filename).read(), filename, 'exec'))
#
# EXAMPLES
#
#   Go into the folder bloft-examples. For each test, copy the .txt files into a
#   new folder and run bloft in it.
#
#
# AUTHOR
#   Ricardo Fabbri <rfabbri@gmail.com>, 3 Dec 2015
#
import bpy
import bpy_extras
import numpy
from mathutils import Matrix
import os
import time
from pathlib import Path

# Create a spline/bezier from a list of points
def new_curve_from_points(p0,name_prefix):
    npts = len(p0)
    c0 = bpy.data.curves.new(name_prefix + 'CurveToLoft', 'CURVE')
    o0 = bpy.data.objects.new(name_prefix + 'CurveToLoft', c0)
    # bpy.context.scene.objects.link(o0)
    bpy.context.scene.collection.objects.link(o0)

    c0.dimensions = "3D"

    spline = o0.data.splines.new('BEZIER')
    spline.bezier_points.add(npts - 1) 
    # ^-- less one because one point is added when the spline is created.
    for p in range(0, npts):
        spline.bezier_points[p].co = spline.bezier_points[p].handle_right = spline.bezier_points[p].handle_left = p0[p]
        # spline.bezier_points[p].co = [p0[p][0], p0[p][1], p0[p][2]]
    return c0, o0, spline 

def read_files():
    pts = []
    i = 0
    fname = 'p' + str(i) + '.txt'
    while os.path.exists(fname):
        print('reading curve ' + fname)
        p = numpy.loadtxt(fname)
        p.tolist()
        pts.append(p)
        i+=1
        fname = 'p' + str(i) + '.txt'
    print('-----')
    print('Read ' + str(i) + ' curves')
    return pts

# to be called inside console after testing
def cleanup():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    
    bpy.ops.outliner.orphans_purge()
    bpy.ops.outliner.orphans_purge()
    bpy.ops.outliner.orphans_purge()

def test():
    print('hello')
    pts = [];
    pts.append([])
    pts[0].append([1, 0, 0])
    pts[0].append([0, 0, 0])
    pts[0].append([0, 1, 0])
    pts.append([])
    pts[1].append([1, 1, 0])
    pts[1].append([0, 1, 0])
    pts[1].append([0, 0, 1])
    loft(pts)

def test1():
    # cleanup()
    pts = read_files()
    loft(pts)
    bpy.ops.export_mesh.ply(filepath='loftsurf.ply')

def loft(pts):
    os = []
    npts = len(pts)
    for i in range(npts):
        c, o, s = new_curve_from_points(pts[i],'curve-p'+str(i))
        # bpy.data.objects[o.name].select = True
        bpy.data.objects[o.name].select_set(True)
        os.append(o)
    # bpy.context.scene.objects.active = bpy.data.objects[os[npts-1].name]
    bpy.context.view_layer.objects.active = bpy.data.objects[os[npts-1].name]

    # join curves into a group
    bpy.ops.object.join('INVOKE_REGION_WIN')
    
    # create a mesh to store the final surface
    me = bpy.data.meshes.new("outputLoft")
    ob = bpy.data.objects.new("outputLoft", me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.context.scene.bsurfaces.SURFSK_mesh = ob
    bpy.context.scene.bsurfaces.SURFSK_curve = bpy.data.objects[os[npts-1].name]
    bpy.context.scene.bsurfaces.SURFSK_guide = 'Curve'

    bpy.context.scene.bsurfaces.SURFSK_edges_U = 20
    bpy.context.scene.bsurfaces.SURFSK_edges_V = 3

    bpy.ops.mesh.surfsk_add_surface('INVOKE_DEFAULT')


def test2():
    p0 = []
    p0.append([0, 1, 0])
    p0.append([1, 1, 0])
    new_curve_from_points(p0,'first-tst')


if __name__ == "__main__":
    print(os.getcwd())
    cleanup()
    inputPrefix = Path("./blender/input/")
    outputPrefix = Path("./blender/output/")
    relation = numpy.loadtxt(inputPrefix / "relation.txt")
    cnt = 0
    for r in relation:

        fname1 = inputPrefix / ("c" + str(int(r[0])) + "_normal.txt")
        fname2 = inputPrefix / ("c" + str(int(r[1])) + "_normal.txt")
        fname3 = inputPrefix / ("c" + str(int(r[1])) + "_reverse.txt")
        if (not os.path.exists(fname1)) or (not os.path.exists(fname2)) or (not os.path.exists(fname3)):
            print("File Miss")
            continue
        pts = []
        pts.append(numpy.loadtxt(fname1).tolist())
        pts.append(numpy.loadtxt(fname2).tolist())
        cleanup()

        tic = time.perf_counter()
        tic = time.perf_counter()
        loft(pts)
        toc = time.perf_counter()
        print(f"Loft {toc - tic:0.4f} seconds")
        bpy.ops.export_mesh.ply(filepath=(outputPrefix / ("loftsurf_" + str(int(r[0])) + "_" + str(int(r[1])) + "_normal.ply")).as_posix())
        cleanup()

        pts = []
        pts.append(numpy.loadtxt(fname1).tolist())
        pts.append(numpy.loadtxt(fname3).tolist())
        cleanup()

        tic = time.perf_counter()
        loft(pts)
        toc = time.perf_counter()
        print(f"Loft {toc - tic:0.4f} seconds")
        bpy.ops.export_mesh.ply(filepath=(outputPrefix / ("loftsurf_" + str(int(r[0])) + "_" + str(int(r[1])) + "_reverse.ply")).as_posix())
        cleanup()

        bpy.ops.wm.quit_blender()


