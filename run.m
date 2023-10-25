tic
disp("Start pre-process")
preProcess_3D_Curves_main;

disp("Start proximity_paring")
proximity_paring;

disp("Start lofting")
loft;

disp("Start gaussian_curvature_filter")
gaussian_curvature_filter;

disp("Start occlusion_consistency_check")
occlusion_consistency_check;

toc

disp("Finished")

