close all; %% close any old figures
mfiledir = fileparts(mfilename('fullpath')); %% get the directory of the current script
cd(mfiledir);

if ~exist(fullfile(pwd, 'tmp'), 'dir') % create a tmp directory to save intermediate results
	mkdir(fullfile(pwd, 'tmp'));
end

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

