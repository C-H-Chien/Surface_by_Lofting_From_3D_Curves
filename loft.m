clear;
close all;
addpath('util/')

input_curves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;
pairs = load(fullfile(pwd, 'tmp', 'curves_proximity_pairs')).curves_proximity_pairs;

if ~exist(fullfile(pwd, 'blender', 'input'), 'dir')
   mkdir(fullfile(pwd, 'blender', 'input'))
end
if exist(fullfile(pwd, 'blender', 'output'), 'dir')
   rmdir(fullfile(pwd, 'blender', 'output'), 's')
   
end
mkdir(fullfile(pwd, 'blender', 'output'))
parfor i = 1:size(pairs, 1)
    n1 = pairs(i, 1);
    n2 = pairs(i, 2);
    c1 = input_curves{n1};
    c2 = input_curves{n2};
    
    fname1 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_normal.ply");
    fname2 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_reverse.ply");
    
    %> loft surface in two possible ways and save
    [vertices, faces] = loft_surface(c1, c2, 0, 10);

    % plot3(c1(:, 1), c1(:, 2), c1(:, 3),"Color",'blue', 'linewidth',3);
    % hold on;
    % plot3(c2(:, 1), c2(:, 2), c2(:, 3), "Color",'blue', 'linewidth',3);
    % scatter3(vertices(:, 1), vertices(:, 2), vertices(:, 3), 20, 'filled', 'red');
    % TR = triangulation(faces, vertices);
    % trisurf(TR, 'FaceColor', 'yellow');
    % hold off

    mesh = surfaceMesh(vertices,faces);
    writeSurfaceMesh(mesh,fname1);

    [vertices, faces] = loft_surface(c1, c2, 1, 10);
    mesh = surfaceMesh(vertices,faces);
    writeSurfaceMesh(mesh,fname2);
end
