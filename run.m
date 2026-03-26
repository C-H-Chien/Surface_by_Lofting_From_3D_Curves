tic
disp("Start pre-process")
preProcess_3D_Curves_main;

%% Get the proximity of pairwise curves
disp("Start proximity_paring")
proximity_paring;

%% Form surface patch hypothesis by lofting
disp("Start lofting")
loft;

%% Compute Gaussian curvature of the surface patch
disp("Start gaussian_curvature_filter")
gaussian_curvature_filter;

%% Do occlusion reasoning
disp("Start occlusion_consistency_check")
occlusion_consistency_check;

toc

disp("Finished")

