clear;
close all;
addpath(fullfile(pwd, 'util'));

% pair proximity
input_curves = load(fullfile(pwd, 'data','ABC-NEF', 'preProcessedCurves.mat')).preProcessedCurves.points;

PARAMS.TAU_ALPHA                           = [0.2 1.3];
PARAMS.PLOT                                = 0;
PARAMS.HAS_GROUND_TRUTH                    = 0;

nCurves = numel(input_curves);
nPairs = nCurves * (nCurves - 1) / 2;
distances = zeros(nPairs, 3);
pairIdx = 1;

%> calculate the distance between every two curves
for ci = 1:nCurves
    for cj = ci + 1:nCurves
        c1 = input_curves{ci};
        c2 = input_curves{cj};
        dis = curve_to_curve_distance_estimation(c1, c2, 20);
        distances(pairIdx, :) = [ci cj dis];
        pairIdx = pairIdx + 1;
    end
end

%> filter based on TAU_ALPHA
curves_proximity_pairs = distances(distances(:, 3) >= PARAMS.TAU_ALPHA(1) & distances(:, 3) <= PARAMS.TAU_ALPHA(2), :);

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

