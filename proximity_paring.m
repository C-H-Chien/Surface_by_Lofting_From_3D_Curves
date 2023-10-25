clear;
close all;
addpath(fullfile(pwd, 'util'));

% pair proximity
input_curves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;

PARAMS.TAU_ALPHA                           = [0.2 1.3];
PARAMS.PLOT                                = 1;
PARAMS.HAS_GROUND_TRUTH                    = 1;

curves_proximity_pairs = [];

distances = [];

for ci = 1:size(input_curves, 2)
    for cj = ci + 1:size(input_curves, 2)
        c1 = input_curves{ci};
        c2 = input_curves{cj};
        dis = curve_to_curve_distance_estimation(c1, c2, 20);
        distances = [distances; [ci cj dis]];
    end
end
curves_proximity_pairs = distances(distances(:, 3) >= PARAMS.TAU_ALPHA(1) & distances(:, 3) <= PARAMS.TAU_ALPHA(2), :);

save(fullfile(pwd, 'tmp', 'curves_proximity_pairs.mat'), "curves_proximity_pairs");

if PARAMS.PLOT 
    histogram(distances(:,3), "NumBins",10);
    hold on;
    if PARAMS.HAS_GROUND_TRUTH
        manual_pick = load(fullfile(pwd, 'data', 'manual_pick.mat')).manual_pick;
        dis = [];
        for i = 1:size(curves_proximity_pairs, 1)
            for j = 1:size(manual_pick, 1)
                if curves_proximity_pairs(i, 1) == manual_pick(j, 1) && curves_proximity_pairs(i, 2) == manual_pick(j, 2)
                    dis = [dis; [manual_pick(j, 1) manual_pick(j, 2) curves_proximity_pairs(i, 3)]];
                end
            end
        end
        histogram(dis(:,3), "EdgeColor","red", "NumBins",10);
    end
    hold off;
end

