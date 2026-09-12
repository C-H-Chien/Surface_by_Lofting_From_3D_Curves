
clearvars -except pipelineTimer timings;

% blender .ply file naming
% loftsurf_1_2_original.ply, loft curve 1 and 2 in the original sequence
% loftsurf_1_2_reverse.ply, loft curve 1 and 2 with curve 2 reversed
addpath(fullfile(pwd, 'util', 'curvatures'));
addpath(fullfile(pwd, 'util', 'plyread/'));
addpath(fullfile(pwd, 'tools', 'projection'));
pairs = load(fullfile(pwd, 'tmp', 'curves_proximity_pairs.mat')).curves_proximity_pairs;
cfg = yaml.loadFile(fullfile(pwd, 'config.yaml'));

PARAMS.PLOT                                = double(cfg.gaussian_filter.plot);
PARAMS.HAS_GROUND_TRUTH                    = double(cfg.gaussian_filter.has_ground_truth);

nPairs = size(pairs, 1);
pairs_after_curvature_filter = -ones(nPairs, 5);
res = nan(nPairs, 4);

parfor i = 1:nPairs
    n1 = pairs(i, 1);
    n2 = pairs(i, 2);
    fname1 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_normal.ply");
    fname2 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_reverse.ply");
    gc1 = nan; gc2 = nan;

    %> calculate curvature of two surface posibility from 1 pair of curves
    try
        [tri,pts] = plyread(fname1,'tri');
        gc1 = mean(curvatures(pts(:, 1), pts(:, 2), pts(:, 3), double(tri)));
    catch ME
        warning('Failed curvature read for %s: %s', fname1, ME.message);
    end
    try
        [tri,pts] = plyread(fname2,'tri');
        gc2 = mean(curvatures(pts(:, 1), pts(:, 2), pts(:, 3), double(tri)));
    catch ME
        warning('Failed curvature read for %s: %s', fname2, ME.message);
    end
    res(i, :) = [n1 n2 gc1 gc2];
end

tau_gaussian_cfg = cfg.gaussian_filter.tau_gaussian;
if ischar(tau_gaussian_cfg) || (isstring(tau_gaussian_cfg) && strcmpi(strtrim(tau_gaussian_cfg), "auto"))
    all_gc = abs([res(:,3); res(:,4)]);
    all_gc = all_gc(~isnan(all_gc));
    use_sigma = isfield(cfg.gaussian_filter, 'tau_gaussian_mode') && strcmpi(strtrim(cfg.gaussian_filter.tau_gaussian_mode), 'mean_sigma');
    if use_sigma
        nsig = 2.0;
        if isfield(cfg.gaussian_filter, 'tau_gaussian_sigma')
            nsig = double(cfg.gaussian_filter.tau_gaussian_sigma);
        end
        PARAMS.TAU_GAUSSIAN = mean(all_gc) + nsig * std(all_gc);
        fprintf('  [auto] tau_gaussian = %.4f (mean + %.1f*std, mean=%.4f std=%.4f)\n', PARAMS.TAU_GAUSSIAN, nsig, mean(all_gc), std(all_gc));
    else
        pct = 70;
        if isfield(cfg.gaussian_filter, 'tau_gaussian_percentile')
            pct = double(cfg.gaussian_filter.tau_gaussian_percentile);
        end
        PARAMS.TAU_GAUSSIAN = prctile(all_gc, pct);
        fprintf('  [auto] tau_gaussian = %.4f (%.0f-th percentile of curvature values)\n', PARAMS.TAU_GAUSSIAN, pct);
    end
else
    PARAMS.TAU_GAUSSIAN = double(tau_gaussian_cfg);
end

for i = 1:nPairs
    n1 = res(i, 1);
    n2 = res(i, 2);
    gc1 = res(i, 3);
    gc2 = res(i, 4);
    % > gc1 is NaN and gc2 is valid, keep gc2 if it is below the threshold
    if isnan(gc1) && (~isnan(gc2)) && abs(gc2) < PARAMS.TAU_GAUSSIAN
        pairs_after_curvature_filter(i, :) = [n1 n2 0 gc1 gc2];
        continue;
    end
    %> If gc2 is NaN and gc1 is valid, keep gc1 if it is below the threshold
    if isnan(gc2) && (~isnan(gc1)) && abs(gc1) < PARAMS.TAU_GAUSSIAN
        pairs_after_curvature_filter(i, :) = [n1 n2 1 gc1 gc2];
        continue;
    end
    
    %> Both valid, keep gc1 if below threshold and smaller than gc2
    if abs(gc1) < PARAMS.TAU_GAUSSIAN && abs(gc1) < abs(gc2)
        pairs_after_curvature_filter(i, :) = [n1 n2 1 gc1 gc2];
        continue;
    end
    %> Both valid, keep gc2 if below threshold and smaller than gc1
    if abs(gc2) < PARAMS.TAU_GAUSSIAN && abs(gc2) < abs(gc1)
        pairs_after_curvature_filter(i, :) = [n1 n2 0 gc1 gc2];
        continue;
    end
    
    % both valid but both equal, keep normal orientaton
    if abs(gc1) < PARAMS.TAU_GAUSSIAN || abs(gc2) < PARAMS.TAU_GAUSSIAN
        pairs_after_curvature_filter(i, :) = [n1 n2 1 gc1 gc2];
        continue;
    end

    % both NaN keep it normal orientation
    if isnan(gc1) && isnan(gc2)
        pairs_after_curvature_filter(i, :) = [n1 n2 1 gc1 gc2];
        continue;
    end

    % same as rules 1 and 2 but with a higher threshold of 165
    if (isnan(gc1) && ~isnan(gc2) && abs(gc2) < 165) || (isnan(gc2) && ~isnan(gc1) && abs(gc1) < 165)
        orient = double(isnan(gc2));
        pairs_after_curvature_filter(i, :) = [n1 n2 orient gc1 gc2];
        continue;
    end

    pairs_after_curvature_filter(i, :) = [-1 -1 -1 -1 -1];
end

%> save
pairs_after_curvature_filter(pairs_after_curvature_filter(:, 1) == -1, :) = [];
save(fullfile(pwd, 'tmp', 'pairs_after_curvature_filter'), "pairs_after_curvature_filter");

%> copy the surviving surfaces into a folder so the evaluation script can be
%  pointed at this stage (same idea as occlusion_consistency_check.m)
outDir = fullfile(pwd, 'tmp', 'surfaces_after_curvature_filter');
if exist(outDir, 'dir')
    rmdir(outDir, 's');
end
mkdir(outDir);
for i = 1:size(pairs_after_curvature_filter, 1)
    n1 = pairs_after_curvature_filter(i, 1);
    n2 = pairs_after_curvature_filter(i, 2);
    if pairs_after_curvature_filter(i, 3) == 1
        surfaceName = "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_normal.ply";
    else
        surfaceName = "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_reverse.ply";
    end
    copyfile(fullfile(pwd, 'blender', 'output', surfaceName), fullfile(outDir, surfaceName));
end

%> plot curvature distribution
if PARAMS.PLOT
    gc = min(abs(res(:, 3:4)), [], 2);
    histogram(gc, "NumBins",40);
    hold on;
    if PARAMS.HAS_GROUND_TRUTH
        manual_pick = load(fullfile(pwd, 'data', 'manual_pick.mat')).manual_pick;
        hitMask = ismember(res(:, 1:2), manual_pick(:, 1:2), 'rows');
        if any(hitMask)
            histogram(min(abs(res(hitMask, 3:4)), [], 2), "EdgeColor","red", "NumBins",10);
        end
    end
    hold off;
end