clear
% blender .ply file naming
% loftsurf_1_2_original.ply, loft curve 1 and 2 in the original sequence
% loftsurf_1_2_reverse.ply, loft curve 1 and 2 with curve 2 reversed
addpath(fullfile(pwd, 'util', 'curvatures'));
addpath(fullfile(pwd, 'util', 'plyread/'));
pairs = load(fullfile(pwd, 'tmp', 'curves_proximity_pairs.mat')).curves_proximity_pairs;
pairs_after_curvature_filter = [];

PARAMS.TAU_GAUSSIAN                        = 0.4;
PARAMS.PLOT                                = 1;
PARAMS.HAS_GROUND_TRUTH                    = 1;

res = [];
for i = 1:size(pairs, 1)
    n1 = pairs(i, 1);
    n2 = pairs(i, 2);
    fname1 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_normal.ply");
    fname2 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_reverse.ply");
    s1 = nan; s2 = nan;
    gc1 = nan; gc2 = nan;
    try
        [tri,pts] = plyread(fname1,'tri');

        gc1 = mean(curvatures(pts(:, 1), pts(:, 2), pts(:, 3), double(tri)));
    end
    try
        [tri,pts] = plyread(fname2,'tri');
        gc2 = mean(curvatures(pts(:, 1), pts(:, 2), pts(:, 3), double(tri)));
    end
    res = [res; [n1 n2 gc1 gc2]];

    if isnan(gc1) && (~isnan(gc2)) && abs(gc2) < PARAMS.TAU_GAUSSIAN
        pairs_after_curvature_filter = [pairs_after_curvature_filter; n1 n2 0 gc1 gc2];
        continue;
    end

    if isnan(gc2) && (~isnan(gc1)) && abs(gc1) < PARAMS.TAU_GAUSSIAN
        pairs_after_curvature_filter = [pairs_after_curvature_filter; n1 n2 1 gc1 gc2];
        continue;
    end

    if abs(gc1) < PARAMS.TAU_GAUSSIAN && abs(gc1) < abs(gc2)
        pairs_after_curvature_filter = [pairs_after_curvature_filter; n1 n2 1 gc1 gc2];
        % copyfile(fname1, "./blender/gaussian/");
        continue;
    end

    if abs(gc2) < PARAMS.TAU_GAUSSIAN && abs(gc2) < abs(gc1)
        pairs_after_curvature_filter = [pairs_after_curvature_filter; n1 n2 0 gc1 gc2];
        % copyfile(fname2, "./blender/gaussian/");
        continue;
    end

    if abs(gc1) < PARAMS.TAU_GAUSSIAN || abs(gc2) < PARAMS.TAU_GAUSSIAN
        pairs_after_curvature_filter = [pairs_after_curvature_filter; n1 n2 1 gc1 gc2];
        % copyfile(fname1, "./blender/gaussian/");
    end
end

save(fullfile(pwd, 'tmp', 'pairs_after_curvature_filter'), "pairs_after_curvature_filter");

if PARAMS.PLOT
    gc = min(abs(res(:, 3:4)), [], 2);
    histogram(gc, "NumBins",40);
    hold on;
    if PARAMS.HAS_GROUND_TRUTH
        manual_pick = load(fullfile(pwd, 'data', 'manual_pick.mat')).manual_pick;
        v = [];
        for i = 1:size(res, 1)
            for j = 1:size(manual_pick, 1)
                if res(i, 1) == manual_pick(j, 1) && res(i, 2) == manual_pick(j, 2)
                    v = [v; res(i, :)];
                end
            end
        end
    end
    histogram(min(abs(v(:, 3:4)), [], 2), "EdgeColor","red", "NumBins",10);
    hold off;
end