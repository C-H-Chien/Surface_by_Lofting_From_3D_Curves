clear;
close all;
addpath('util/')

input_curves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;
pairs = load(fullfile(pwd, 'tmp', 'curves_proximity_pairs')).curves_proximity_pairs;

if ~exist(fullfile(pwd, 'blender', 'input'), 'dir')
   mkdir(fullfile(pwd, 'blender', 'input'))
end
if ~exist(fullfile(pwd, 'blender', 'output'), 'dir')
   mkdir(fullfile(pwd, 'blender', 'output'))
end

for i = 1:size(pairs, 1)
    n1 = pairs(i, 1);
    n2 = pairs(i, 2);
    c1 = input_curves{n1};
    c2 = input_curves{n2};
    
    fname1 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_normal.ply");
    fname2 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_reverse.ply");

    [vertices, faces] = loft_surface(c1, c2, 0, 10);
    mesh = surfaceMesh(vertices,faces);
    writeSurfaceMesh(mesh,fname1);

    [vertices, faces] = loft_surface(c1, c2, 1, 10);
    mesh = surfaceMesh(vertices,faces);
    writeSurfaceMesh(mesh,fname2);
end
