close all; %% close any old figures
mfiledir = fileparts(mfilename('fullpath')); %% get the directory of the current script
cd(mfiledir);

if ~exist(fullfile(pwd, 'tmp'), 'dir') % create a tmp directory to save intermediate results
	mkdir(fullfile(pwd, 'tmp'));
end

pipelineTimer = tic;
timings = struct();

disp("Start pre-process")
tic
preProcess_3D_Curves_main;
timings.pre_process = toc;

%% Get the proximity of pairwise curves
disp("Start proximity_paring")
tic
proximity_paring;
timings.proximity_paring = toc;

%% Form surface patch hypothesis by lofting
disp("Start lofting")
tic
loft;
timings.lofting = toc;

%% Compute Gaussian curvature of the surface patch
disp("Start gaussian_curvature_filter")
tic
gaussian_curvature_filter;
timings.gaussian_curvature_filter = toc;

%% 2D occlusion reasoning: per (view, surface) cross-rotation point validation
disp("Start Cross_Rotation_point_validation")
tic
Cross_Rotation_point_validation;
timings.cross_rotation = toc;

%% Filter surfaces from the cross-rotation results (Otsu)
disp("Start Occlusion_2D_filter")
tic
Occlusion_2D_filter;
timings.occlusion_2d_filter = toc;

timings.total = toc(pipelineTimer);

disp("---------------- Timing Summary (seconds) ----------------")
fprintf("preProcess_3D_Curves_main:      %.3f\n", timings.pre_process);
fprintf("proximity_paring:               %.3f\n", timings.proximity_paring);
fprintf("loft:                           %.3f\n", timings.lofting);
fprintf("gaussian_curvature_filter:      %.3f\n", timings.gaussian_curvature_filter);
fprintf("Cross_Rotation_point_validation:%.3f\n", timings.cross_rotation);
fprintf("Occlusion_2D_filter:            %.3f\n", timings.occlusion_2d_filter);
fprintf("TOTAL:                          %.3f\n", timings.total);
disp("----------------------------------------------------------")

%% ------------------------------------------------------------------
%% Evaluation at the three pipeline points.
%% Each point is just a folder of .ply files that already exists:
%%   1. blender/output                        - all lofted surfaces (before curvature filter)
%%   2. tmp/surfaces_after_curvature_filter    - after curvature filter / before occlusion check
%%   3. tmp/filtered_surfaces                  - after occlusion check (final output)
%% ------------------------------------------------------------------
%% (defined here, not at the top, because the pipeline scripts call `clearvars`)
gt_file = fullfile(pwd, 'data', 'ABC-NEF', '00000325', ...
    '00000325_3062bccff48e47a2b9de05e3_trimesh_020.obj');

eval_stage("Baseline (pre gaussian_curvature_filter)",     fullfile(pwd, 'blender', 'output'), gt_file);
eval_stage("Gaussian Curvature (pre occlusion_consistency)", fullfile(pwd, 'tmp', 'surfaces_after_curvature_filter'), gt_file);
eval_stage("Occlusion Consistency (final)",                 fullfile(pwd, 'tmp', 'filtered_surfaces'), gt_file);

%% Surface counts at each pipeline point (shown last)
nLoft       = count_ply(fullfile(pwd, 'blender', 'output'));
nCurvature  = count_ply(fullfile(pwd, 'tmp', 'surfaces_after_curvature_filter'));
nOcclusion  = count_ply(fullfile(pwd, 'tmp', 'filtered_surfaces'));
disp("---------------- Surface Counts ----------------")
fprintf("After loft (blender/output):                     %d\n", nLoft);
fprintf("After gaussian_curvature_filter (surfaces_after_curvature_filter): %d  (removed %d)\n", nCurvature, nLoft - nCurvature);
fprintf("After Occlusion_2D_filter (filtered_surfaces):   %d  (removed %d)\n", nOcclusion, nCurvature - nOcclusion);
disp("------------------------------------------------------------------------")

disp("Finished")

function n = count_ply(plyDir)
    n = numel(dir(fullfile(plyDir, '*.ply')));
end

function eval_stage(label, plyDir, gt_file)
    fprintf('\n===== Evaluation: %s =====\n', label);
    script = fullfile(pwd, 'evaluation', 'eval_surfaces_main.py');
    cmd = sprintf('python "%s" --mode point --gt-file "%s" --filtered-dir "%s" --tau 0.02', ...
        script, gt_file, plyDir);
    status = system(cmd);
    if status ~= 0
        warning('eval_stage:failed', 'Evaluation for "%s" exited with status %d', label, status);
    end
end