clear;
close all;

% Unified lofting pipeline:
% - Reads all parameters from config.yaml once (or uses built-in defaults)
% - Runs all steps in-memory (no intermediate .mat dependencies)
% - Keeps output folders and final artifacts compatible with existing workflow

mfiledir = fileparts(mfilename('fullpath'));
cd(mfiledir);

% Add paths used across the original scripts
addpath(fullfile(pwd, 'util'));
addpath(fullfile(pwd, 'util', 'curvatures'));
addpath(fullfile(pwd, 'util', 'TriangleRayIntersection'));
addpath(fullfile(pwd, 'util', 'plyread'));
addpath(fullfile(pwd, 'util', 'rayBoxIntersection'));

% YAML loader shipped in repo under tools/projection/+yaml
addpath(fullfile(pwd, 'tools', 'projection'));

cfgPath = fullfile(pwd, 'config.yaml');
if exist(cfgPath, 'file')
    cfg = yaml.loadFile(cfgPath);
else
    cfg = default_config();
end
cfg = resolve_dataset_defaults(cfg);
rng(0);

if ~exist(fullfile(pwd, 'tmp'), 'dir')
    mkdir(fullfile(pwd, 'tmp'));
end

tic;
disp("Start pre-process");
preProcessedCurves = step_preprocess(cfg);

disp("Start proximity_paring");
curves_proximity_pairs = step_proximity_paring(cfg, preProcessedCurves.points);

disp("Start lofting");
step_loft(preProcessedCurves.points, curves_proximity_pairs);

disp("Start gaussian_curvature_filter");
pairs_after_curvature_filter = step_gaussian_filter(cfg, curves_proximity_pairs);

disp("Start occlusion_consistency_check");
step_occlusion_check(cfg, preProcessedCurves, pairs_after_curvature_filter);

toc;
disp("Finished");

function cfg = default_config()
    cfg.dataset.name = "ABC-NEF";
    cfg.dataset.scene = "00000325";
    cfg.dataset.curve_graph_file = "curve_graph_ABC_NEF_00000325.mat";
    cfg.dataset.num_views = 50;

    cfg.preprocess.smoothing = 0;
    cfg.preprocess.smoothing_window = 500;
    cfg.preprocess.apply_length_constraints = 0;
    cfg.preprocess.tau_length = 0.15;
    cfg.preprocess.tau_num_of_pts = 500;
    cfg.preprocess.gaussian_derivative_sigma = 10;
    cfg.preprocess.gaussian_derivative_data_range = 20;
    cfg.preprocess.break_curves = 0;
    cfg.preprocess.min_break_curvature = 0.0025;
    cfg.preprocess.plot = 1;
    cfg.preprocess.debug = 1;
    cfg.preprocess.debug_colormap_curve_index = 10;
    cfg.preprocess.plot_3d_tangents = 0;
    cfg.preprocess.save_curves_after_length_constraint = 0;

    cfg.proximity.tau_alpha_min = 0.2;
    cfg.proximity.tau_alpha_max = 1.3;
    cfg.proximity.plot = 0;
    cfg.proximity.has_ground_truth = 0;

    cfg.gaussian_filter.tau_gaussian = 0.35;
    cfg.gaussian_filter.plot = 0;
    cfg.gaussian_filter.has_ground_truth = 1;

    cfg.occlusion.tau_orientation = 0.17453;
    cfg.occlusion.tau_distance = 3;
    cfg.occlusion.tau_distance_diff = 0.2;
    cfg.occlusion.generate_matches = 1;
    cfg.occlusion.ray_tracing = 1;
    cfg.occlusion.surface_filtering = 1;
    cfg.occlusion.surface_filtering_threshold = 200;
    cfg.occlusion.save_match_plot_2d = 0;
    cfg.occlusion.show_plot_match = 0;
    cfg.occlusion.plot_match_view = 10;
    cfg.occlusion.img_rows = 800;
    cfg.occlusion.img_cols = 800;
end

function cfg = resolve_dataset_defaults(cfg)
    if ~isfield(cfg, 'dataset')
        cfg.dataset = default_config().dataset;
    end

    if ~isfield(cfg.dataset, 'name') || strlength(string(cfg.dataset.name)) == 0
        cfg.dataset.name = "ABC-NEF";
    end

    datasetRoot = fullfile(pwd, 'data', string(cfg.dataset.name));

    if (~isfield(cfg.dataset, 'scene')) || strcmpi(string(cfg.dataset.scene), "auto") || strlength(string(cfg.dataset.scene)) == 0
        d = dir(datasetRoot);
        d = d([d.isdir]);
        names = string({d.name});
        names = names(~ismember(names, [".", ".."]));
        if any(names == "00000325")
            cfg.dataset.scene = "00000325";
        elseif ~isempty(names)
            cfg.dataset.scene = names(1);
        else
            error('No scene folder found under data/%s.', string(cfg.dataset.name));
        end
    end

    if (~isfield(cfg.dataset, 'curve_graph_file')) || strcmpi(string(cfg.dataset.curve_graph_file), "auto") || strlength(string(cfg.dataset.curve_graph_file)) == 0
        sceneName = string(cfg.dataset.scene);
        candidate = fullfile(datasetRoot, "curve_graph_ABC_NEF_" + sceneName + ".mat");
        if exist(candidate, 'file')
            cfg.dataset.curve_graph_file = "curve_graph_ABC_NEF_" + sceneName + ".mat";
        else
            g = dir(fullfile(datasetRoot, 'curve_graph*.mat'));
            if ~isempty(g)
                cfg.dataset.curve_graph_file = string(g(1).name);
            else
                error('No curve_graph*.mat file found under data/%s.', string(cfg.dataset.name));
            end
        end
    end

    if (~isfield(cfg.dataset, 'num_views')) || double(cfg.dataset.num_views) <= 0
        sceneRoot = fullfile(datasetRoot, string(cfg.dataset.scene), 'projection_matrix');
        p = dir(fullfile(sceneRoot, '*.projmatrix'));
        if isempty(p)
            cfg.dataset.num_views = 50;
        else
            cfg.dataset.num_views = numel(p);
        end
    end
end

function preProcessedCurves = step_preprocess(cfg)
    dataset = string(cfg.dataset.name);
    if isfield(cfg.dataset, 'curve_graph_file')
        curve_graph_file = string(cfg.dataset.curve_graph_file);
    else
        curve_graph_file = "curve_graph_ABC_NEF_00000325.mat";
    end
    input_curves = load(fullfile(pwd, 'data', dataset, curve_graph_file)).complete_curve_graph;

    PARAMS.SMOOTHING                           = double(cfg.preprocess.smoothing);
    PARAMS.SMOOTHING_ACROSS_NUM_OF_DATA        = double(cfg.preprocess.smoothing_window);
    PARAMS.APPLY_LENGTH_CONSTRAINTS            = double(cfg.preprocess.apply_length_constraints);
    PARAMS.TAU_LENGTH                          = double(cfg.preprocess.tau_length);
    PARAMS.TAU_NUM_OF_PTS                      = double(cfg.preprocess.tau_num_of_pts);
    PARAMS.GAUSSIAN_DERIVATIVE_SIGMA           = double(cfg.preprocess.gaussian_derivative_sigma);
    PARAMS.GAUSSIAN_DERIVATIVE_DATA_RANGE      = double(cfg.preprocess.gaussian_derivative_data_range);
    PARAMS.BREAK                               = double(cfg.preprocess.break_curves);
    PARAMS.MIN_BREAK_CURVATURE                 = double(cfg.preprocess.min_break_curvature);
    PARAMS.PLOT                                = double(cfg.preprocess.plot);
    PARAMS.DEBUG                               = double(cfg.preprocess.debug);
    PARAMS.DEBUG_COLORMAP_CURVE_INDEX          = double(cfg.preprocess.debug_colormap_curve_index);
    PARAMS.PLOT_3D_TANGENTS                    = double(cfg.preprocess.plot_3d_tangents);
    PARAMS.SAVE_CURVES_AFTER_LENGTH_CONSTRAINT = double(cfg.preprocess.save_curves_after_length_constraint);

    if PARAMS.SMOOTHING == 1
        smoothed_curves = cell(length(input_curves), 2);
        for ci = 1:length(input_curves)
            c = input_curves{ci};
            smoothed_curves{ci} = smoothdata(c, "gaussian", PARAMS.SMOOTHING_ACROSS_NUM_OF_DATA);
        end
    else
        smoothed_curves = input_curves;
    end

    if PARAMS.APPLY_LENGTH_CONSTRAINTS == 1
        curves_after_length_filter = filter_by_length(smoothed_curves, PARAMS.TAU_LENGTH, PARAMS.TAU_NUM_OF_PTS);
    else
        curves_after_length_filter = smoothed_curves;
    end

    tangents = cell(1, size(curves_after_length_filter, 2));
    curvatures = cell(1, size(curves_after_length_filter, 2));
    for ci = 1:length(curves_after_length_filter)
        curve = curves_after_length_filter{ci};
        [T, k] = get_UnitTangents_Curvatures(curve(:,1), curve(:,2), curve(:,3), PARAMS);
        tangents{ci} = T;
        curvatures{ci} = k;
    end

    breakPoints = cell(1, length(curves_after_length_filter));
    if PARAMS.BREAK == 1
        for ci = 1:length(curves_after_length_filter)
            curve = curves_after_length_filter{ci};
            TF = islocalmax(curvatures{ci}, 'MinSeparation',PARAMS.TAU_NUM_OF_PTS,...
                'MinProminence',max(min(maxk(curvatures{ci}, floor(0.1 * size(curvatures{ci}, 1)))), PARAMS.MIN_BREAK_CURVATURE));
            breakPoints{ci} = TF;
        end

        preProcessedCurves.points = {};
        preProcessedCurves.curvatures = {};
        preProcessedCurves.tangents = {};
        for ci = 1:length(curves_after_length_filter)
            TF = breakPoints{ci};
            curve = curves_after_length_filter{ci};
            bp = find(TF ~= 0);
            if isempty(bp) || bp(end) ~= size(curve, 1)
                bp = [bp; size(curve, 1)];
            end
            p = 1;
            for bpi = 1:size(bp, 1)
                c = curve(p:bp(bpi), :);
                if ~isempty(filter_by_length({c}, PARAMS.TAU_LENGTH, PARAMS.TAU_NUM_OF_PTS))
                    preProcessedCurves.points{end + 1} = c;
                    preProcessedCurves.curvatures{end + 1} = curvatures{ci}(p:bp(bpi), :);
                    preProcessedCurves.tangents{end + 1} = tangents{ci}(p:bp(bpi), :);
                end
                p = bp(bpi) + 1;
            end
        end
    else
        preProcessedCurves.points = curves_after_length_filter;
        preProcessedCurves.curvatures = curvatures;
        preProcessedCurves.tangents = tangents;
    end

    if PARAMS.SAVE_CURVES_AFTER_LENGTH_CONSTRAINT == 1
        save(fullfile(pwd, 'tmp', 'curves_after_length_filter.mat'), "curves_after_length_filter");
    end
end

function curves_proximity_pairs = step_proximity_paring(cfg, input_curves)
    PARAMS.TAU_ALPHA        = [double(cfg.proximity.tau_alpha_min), double(cfg.proximity.tau_alpha_max)];
    PARAMS.PLOT             = double(cfg.proximity.plot);
    PARAMS.HAS_GROUND_TRUTH = double(cfg.proximity.has_ground_truth);

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
end

function step_loft(input_curves, pairs)
    if ~exist(fullfile(pwd, 'blender', 'input'), 'dir')
        mkdir(fullfile(pwd, 'blender', 'input'));
    end
    if exist(fullfile(pwd, 'blender', 'output'), 'dir')
        rmdir(fullfile(pwd, 'blender', 'output'), 's');
    end
    mkdir(fullfile(pwd, 'blender', 'output'));

    parfor i = 1:size(pairs, 1)
        n1 = pairs(i, 1);
        n2 = pairs(i, 2);
        c1 = input_curves{n1};
        c2 = input_curves{n2};

        fname1 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_normal.ply");
        fname2 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_reverse.ply");

        [vertices, faces] = loft_surface(c1, c2, 0, 10);
        mesh = surfaceMesh(vertices,faces);
        writeSurfaceMesh(mesh,fname1);

        [vertices, faces] = loft_surface(c1, c2, 1, 10);
        mesh = surfaceMesh(vertices,faces);
        writeSurfaceMesh(mesh,fname2);
    end
end

function pairs_after_curvature_filter = step_gaussian_filter(cfg, pairs)
    PARAMS.TAU_GAUSSIAN     = double(cfg.gaussian_filter.tau_gaussian);
    PARAMS.PLOT             = double(cfg.gaussian_filter.plot);
    PARAMS.HAS_GROUND_TRUTH = double(cfg.gaussian_filter.has_ground_truth);

    pairs_after_curvature_filter = [];
    res = [];
    parfor i = 1:size(pairs, 1)
        n1 = pairs(i, 1);
        n2 = pairs(i, 2);
        fname1 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_normal.ply");
        fname2 = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(n1) + "_" + int2str(n2) + "_reverse.ply");
        gc1 = nan;
        gc2 = nan;

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
            pairs_after_curvature_filter(i, :) = [n1 n2 0 gc1 gc2];
            continue;
        end

        if isnan(gc2) && (~isnan(gc1)) && abs(gc1) < PARAMS.TAU_GAUSSIAN
            pairs_after_curvature_filter(i, :) = [n1 n2 1 gc1 gc2];
            continue;
        end

        if abs(gc1) < PARAMS.TAU_GAUSSIAN && abs(gc1) < abs(gc2)
            pairs_after_curvature_filter(i, :) = [n1 n2 1 gc1 gc2];
            continue;
        end

        if abs(gc2) < PARAMS.TAU_GAUSSIAN && abs(gc2) < abs(gc1)
            pairs_after_curvature_filter(i, :) = [n1 n2 0 gc1 gc2];
            continue;
        end

        if abs(gc1) < PARAMS.TAU_GAUSSIAN || abs(gc2) < PARAMS.TAU_GAUSSIAN
            pairs_after_curvature_filter(i, :) = [n1 n2 1 gc1 gc2];
            continue;
        end

        pairs_after_curvature_filter(i, :) = [-1 -1 -1 -1 -1];
    end

    pairs_after_curvature_filter(pairs_after_curvature_filter(:, 1) == -1, :) = [];
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
                        v = [v; min(abs(res(i, 3)), abs(res(i, 4)))];
                    end
                end
            end
            histogram(v, "NumBins",40, "FaceColor",'red');
        end
        hold off;
    end
end

function step_occlusion_check(cfg, preProcessedCurves, pairs)
    PARAMS.TAU_ORIENTATION             = double(cfg.occlusion.tau_orientation);
    PARAMS.TAU_DISTANCE                = double(cfg.occlusion.tau_distance);
    PARAMS.TAU_DISTANCE_DIFF           = double(cfg.occlusion.tau_distance_diff);
    PARAMS.GENERATE_MATCHES            = double(cfg.occlusion.generate_matches);
    PARAMS.RAY_TRACING                 = double(cfg.occlusion.ray_tracing);
    PARAMS.SURFACE_FILTERING           = double(cfg.occlusion.surface_filtering);
    PARAMS.SURFACE_FILTERING_THRESHOLD = double(cfg.occlusion.surface_filtering_threshold);
    PARAMS.SAVE_MATCH_PLOT_2D          = double(cfg.occlusion.save_match_plot_2d);
    PARAMS.SHOW_PLOT_MATCH             = double(cfg.occlusion.show_plot_match);
    PARAMS.PLOT_MATCH_VIEW             = double(cfg.occlusion.plot_match_view);
    PARAMS.IMG_ROWS                    = double(cfg.occlusion.img_rows);
    PARAMS.IMG_COLS                    = double(cfg.occlusion.img_cols);

    pic_size = [PARAMS.IMG_ROWS, PARAMS.IMG_COLS];
    dataset_name = string(cfg.dataset.name);
    scene_name = string(cfg.dataset.scene);
    viewCnt = double(cfg.dataset.num_views);

    curves = preProcessedCurves.points;
    tangents = preProcessedCurves.tangents;

    [pixel_offset_col,pixel_offset_row] = meshgrid(-PARAMS.TAU_DISTANCE:PARAMS.TAU_DISTANCE,-PARAMS.TAU_DISTANCE:PARAMS.TAU_DISTANCE);
    pixel_offset_row = reshape(pixel_offset_row, [], 1);
    pixel_offset_col = reshape(pixel_offset_col, [], 1);

    curvesProj_view = {};
    matchCurves_view = {};
    unmatchCurves_view = {};
    edgeList_view = {};

    if PARAMS.GENERATE_MATCHES == 1
        parfor view = 1:viewCnt
            fname1 = fullfile(pwd, 'data', dataset_name, scene_name, "projection_matrix", sprintf("%02d.projmatrix", view-1));
            fname2 = fullfile(pwd, 'data', dataset_name, scene_name, 'edges', sprintf("edges_%02d.mat", view-1));
            projMatrix = load(fname1);
            edge = load(fname2).TO_edges;

            [K, RT] = Pdecomp(projMatrix);
            R_t = RT(1:3,1:3);
            T_t = RT(1:3, 4);
            C_t = -R_t' * T_t;

            edgeList_view{view} = edge;
            tangentProj = cell(size(tangents));
            curvesProj = nan([pic_size, 5]);
            curveCam = cell(size(curves));

            for ci = 1:size(curves, 2)
                tangentProj{ci} = tangent_projection(curves{ci}, tangents{ci}, projMatrix);

                cp = [curves{ci}'; ones(1, size(curves{ci}, 1))];
                cp = RT * cp;
                curveCam{ci} = cp';

                pointProj = K * cp;
                pointProj = pointProj(1:2, :) ./ pointProj(3, :);

                for pp = 1:size(pointProj, 2)
                    r = floor(pointProj(2, pp) + 1);
                    c = floor(pointProj(1, pp) + 1);
                    if r >= 1 && r <= pic_size(1) && c >= 1 && c <= pic_size(2)
                        if isnan(curvesProj(r, c, 2)) || curvesProj(r, c, 2) > sqrt(sum(curveCam{ci}(pp, :).^2))
                            curvesProj(r, c, 1) = tangentProj{ci}(pp);
                            curvesProj(r, c, 2) = sqrt(sum(curveCam{ci}(pp, :).^2));
                            curvesProj(r, c, 3:5) = curves{ci}(pp, :);
                        end
                    end
                end
            end

            edge_bucket = NaN(pic_size);
            for i = 1:size(edge, 1)
                r = floor(edge(i, 2) + 1);
                c = floor(edge(i, 1) + 1);
                for k = 1:size(pixel_offset_col, 1)
                    nr = r + pixel_offset_row(k);
                    nc = c + pixel_offset_col(k);
                    if nr < 1 || nr > pic_size(1) || nc < 1 || nc > pic_size(2)
                        continue;
                    end
                    edge_bucket(nr, nc) = edge(i, 3);
                end
            end

            match = [];
            unmatch = [];
            for i = 1:pic_size(1)
                for j = 1:pic_size(2)
                    if isnan(curvesProj(i, j))
                        continue;
                    end
                    dir = reshape(curvesProj(i, j, 3:5), 1, []) - C_t';
                    record = [pic_size(1) - i, j-1, C_t', dir ./ norm(dir), curvesProj(i, j, 2)];

                    if isnan(edge_bucket(i, j))
                        unmatch = [unmatch; record];
                        continue;
                    end

                    diff = angdiff(curvesProj(i, j, 1), edge_bucket(i, j));
                    diff = abs(diff);
                    diff = min(diff, pi - diff);
                    if diff < PARAMS.TAU_ORIENTATION
                        match = [match; record];
                    else
                        unmatch = [unmatch; record];
                    end
                end
            end

            matchCurves_view{view} = match;
            unmatchCurves_view{view} = unmatch;
            curvesProj_view{view} = curvesProj;
            fprintf("Finished curve matching in view %d\n", view-1);
        end

    else
        error('generate_matches=0 requires external curve match cache, which is disabled in run_pipeline.m. Set occlusion.generate_matches=1 in config.yaml.');
    end

    if PARAMS.SAVE_MATCH_PLOT_2D == 1
        if ~exist(fullfile(pwd, 'tmp', 'figures'), 'dir')
            mkdir(fullfile(pwd, 'tmp', 'figures'));
        end
        f = figure('visible','off');
        for plotView = 1:viewCnt
            scatter(matchCurves_view{plotView}(:, 2), matchCurves_view{plotView}(:, 1),2,'red', 'filled');
            hold on;
            scatter(edgeList_view{plotView}(:, 1), (1200 * ones(size(edgeList_view{plotView}(:, 2)))) - edgeList_view{plotView}(:, 2),1,'green', 'filled');
            hold off;
            saveas(f,fullfile(pwd, 'tmp', 'figures', sprintf("matchCurves_view_%d", plotView - 1)),'jpg');
        end
        close(f);
    end

    if PARAMS.SHOW_PLOT_MATCH == 1
        plotView = PARAMS.PLOT_MATCH_VIEW;
        for i = 1:size(curves, 2)
            scatter3(curves{i}(:, 1), curves{i}(:, 2), curves{i}(:, 3), 1, 'green', 'filled');
            hold on;
        end

        cp = matchCurves_view{plotView}(:, 6:8) .*  [matchCurves_view{plotView}(:, 9) matchCurves_view{plotView}(:, 9) matchCurves_view{plotView}(:, 9)];
        cp = cp + matchCurves_view{plotView}(:, 3:5);
        scatter3(cp(:, 1), cp(:, 2), cp(:, 3), 3, 'red', 'filled');

        ccenter = matchCurves_view{plotView}(1, 3:5);
        scatter3(ccenter(1), ccenter(2), ccenter(3), 40, 'red', 'filled');
        text(ccenter(1), ccenter(2), ccenter(3),sprintf("%d", plotView));
        hold off;
    end

    if PARAMS.RAY_TRACING  == 1
        surface_intersection_count = zeros(size(pairs, 1), 1);
        parfor i = 1:size(pairs, 1)
            c1 = pairs(i, 1);
            c2 = pairs(i, 2);

            surfaceName = "loftsurf_" + int2str(c1) + "_" + int2str(c2) + "_";
            if(pairs(i, 3) == 1)
                surfaceName = surfaceName + "normal.ply";
            else
                surfaceName = surfaceName + "reverse.ply";
            end

            try
                [tri,pts] = plyread(fullfile(pwd, 'blender', 'output', surfaceName),'tri');
            catch
                continue;
            end

            bbox_vmin = min(pts);
            bbox_vmax = max(pts);
            for v = 1:viewCnt
                for k = 1:size(matchCurves_view{v}, 1)
                    ct = matchCurves_view{v}(k, 3:5);
                    dir = matchCurves_view{v}(k, 6:8);
                    dis = matchCurves_view{v}(k, 9);

                    interset = rayBoxIntersection(ct, dir, bbox_vmin, bbox_vmax);
                    if ~interset
                        continue;
                    end

                    [intersect, t] = TriangleRayIntersection(ct, dir, pts(tri(:, 1), :), pts(tri(:, 2), :), pts(tri(:, 3), :), 'lineType' , 'ray');
                    intersectPointIdx = find(intersect == 1);
                    if isempty(intersectPointIdx)
                        continue;
                    end

                    diff = dis - t(intersectPointIdx);
                    if ~isempty(find(diff > PARAMS.TAU_DISTANCE_DIFF, 1))
                        surface_intersection_count(i) = surface_intersection_count(i) + 1;
                    end
                end
            end
            fprintf("Finished %s\n", surfaceName);
        end
    else
        error('ray_tracing=0 requires external cache, which is disabled in run_pipeline.m. Set occlusion.ray_tracing=1 in config.yaml.');
    end

    if PARAMS.SURFACE_FILTERING == 1
        if exist(fullfile(pwd, 'tmp', 'filtered_surfaces'), 'dir')
            rmdir((fullfile(pwd, 'tmp', 'filtered_surfaces')), 's');
        end
        mkdir(fullfile(pwd, 'tmp', 'filtered_surfaces'));

        cnt = 0;
        for i = 1:size(pairs, 1)
            if surface_intersection_count(i) > PARAMS.SURFACE_FILTERING_THRESHOLD
                continue;
            end

            c1 = pairs(i, 1);
            c2 = pairs(i, 2);
            surfaceName = "loftsurf_" + int2str(c1) + "_" + int2str(c2) + "_";
            if(pairs(i, 3) == 1)
                surfaceName = surfaceName + "normal.ply";
            else
                surfaceName = surfaceName + "reverse.ply";
            end

            copyfile(fullfile(pwd, 'blender', 'output', surfaceName), fullfile(pwd, 'tmp', 'filtered_surfaces', surfaceName));
            cnt = cnt + 1;
        end
        fprintf("Surface number after filtering: %d\n", cnt);
    end
end
