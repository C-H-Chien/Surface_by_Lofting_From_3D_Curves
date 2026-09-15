
close all;
clearvars -except pipelineTimer timings;

addpath(fullfile(pwd, 'util'));
addpath(fullfile(pwd, 'tools', 'projection'));

cfg = yaml.loadFile(fullfile(pwd, 'config.yaml'));

% pair proximity
input_curves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;

PARAMS.TAU_ALPHA_MIN    = double(cfg.proximity.tau_alpha_min);
PARAMS.PLOT             = double(cfg.proximity.plot);
PARAMS.HAS_GROUND_TRUTH = double(cfg.proximity.has_ground_truth);

nCurves = numel(input_curves);
nPairs = nCurves * (nCurves - 1) / 2;
distances = zeros(nPairs, 3);
pairIdx = 1;

%> calculate the distance between every two curves
for ci = 1:nCurves
    for cj = ci + 1:nCurves
        c1 = input_curves{ci};
        c2 = input_curves{cj};
        dis = curve_to_curve_distance_estimation(c1, c2, 50);
        distances(pairIdx, :) = [ci cj dis];
        pairIdx = pairIdx + 1;
    end
end

tau_max_cfg = cfg.proximity.tau_alpha_max;
if ischar(tau_max_cfg) || (isstring(tau_max_cfg) && strcmpi(strtrim(tau_max_cfg), "auto"))
    use_sigma = isfield(cfg.proximity, 'tau_alpha_mode') && strcmpi(strtrim(cfg.proximity.tau_alpha_mode), 'mean_sigma');
    if use_sigma
        nsig = 2.0;
        if isfield(cfg.proximity, 'tau_alpha_sigma')
            nsig = double(cfg.proximity.tau_alpha_sigma);
        end
        d = distances(:, 3);
        tau_alpha_max = mean(d) + nsig * std(d);
        fprintf('  [auto] tau_alpha_max = %.4f (mean + %.1f*std, mean=%.4f std=%.4f)\n', tau_alpha_max, nsig, mean(d), std(d));
    else
        pct = 75;
        if isfield(cfg.proximity, 'tau_alpha_percentile')
            pct = double(cfg.proximity.tau_alpha_percentile);
        end
        tau_alpha_max = prctile(distances(:, 3), pct);
        fprintf('  [auto] tau_alpha_max = %.4f (%.0f-th percentile of %d distances)\n', tau_alpha_max, pct, nPairs);
    end
else
    tau_alpha_max = double(tau_max_cfg);
end

%> curves_proximity_pairs = distances(distances(:, 3) >= PARAMS.TAU_ALPHA_MIN & distances(:, 3) <= tau_alpha_max, :);
curves_proximity_pairs = distances;

save(fullfile(pwd, 'tmp', 'curves_proximity_pairs.mat'), "curves_proximity_pairs");

%> plot distance distribution
if PARAMS.PLOT 
    histogram(distances(:,3), "NumBins",10);
    hold on;
    if PARAMS.HAS_GROUND_TRUTH
        manual_pick = load(fullfile(pwd, 'data', 'manual_pick.mat')).manual_pick;
        hitMask = ismember(curves_proximity_pairs(:, 1:2), manual_pick(:, 1:2), 'rows');
        if any(hitMask)
            histogram(curves_proximity_pairs(hitMask, 3), "EdgeColor","red", "NumBins",10);
        end
    end
    hold off;
end

