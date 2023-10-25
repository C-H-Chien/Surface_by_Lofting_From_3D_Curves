clear;
close all;
tic;
addpath(fullfile(pwd, 'util'));
addpath(fullfile(pwd, 'util', 'TriangleRayIntersection'));
addpath(fullfile(pwd, 'util', 'plyread/'));

PARAMS.TAU_ORIENTATION                     = pi/18; %> 5 deg
PARAMS.TAU_DISTANCE                        = 3; %> 5 pixels
PARAMS.GENERATE_MATCHES                    = 1;
PARAMS.RAY_TRACING                         = 1;
PARAMS.SURFACE_FILTERING                   = 1;
PARAMS.SURFACE_FILTERING_THRESHOLD         = 300;
PARAMS.SAVE_MATCH_PLOT_2D                  = 1;
PARAMS.SHOW_PLOT_MATCH                     = 0;
PARAMS.PLOT_MATCH_VIEW                     = 10;

% load curves
curves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;
% load tangents
tangents = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.tangents;
% load pairs
pairs = load("./tmp/pairs_after_curvature_filter.mat").pairs_after_curvature_filter;

[pixel_offset_col,pixel_offset_row] = meshgrid(-PARAMS.TAU_DISTANCE:PARAMS.TAU_DISTANCE,-PARAMS.TAU_DISTANCE:PARAMS.TAU_DISTANCE);
pixel_offset_row = reshape(pixel_offset_row, [], 1);
pixel_offset_col = reshape(pixel_offset_col, [], 1);

viewCnt = 0;
curvesProj_view = {};
matchCurves_view = {};
unmatchCurves_view = {};
edgeList_view = {};

if PARAMS.GENERATE_MATCHES == 1
    while 1
        fname1 = fullfile(pwd, 'data','amsterdam-house-full', sprintf("%02d.projmatrix", viewCnt));
        fname2 = fullfile(pwd, 'data', 'TO_Edges_Amsterdam_House', sprintf("%02d.mat", viewCnt));
        fname3 = fullfile(pwd, 'data', 'amsterdam-house-full', sprintf( "%02d.jpg", viewCnt ));
        try
            projMatrix = load(fname1);
            edge = load(fname2).TO_edges;
            pic_size = size(imread(fname3), 1:2);
        catch
            break;
        end
        [K, RT] = Pdecomp(projMatrix);
        R_t = RT(1:3,1:3);
        T_t = RT(1:3, 4);
    
        C_t = -R_t' * T_t;  %> Camera position in world coord
    
        edgeList_view{end + 1} = edge;
        tangentProj = cell(size(tangents));
        curvesProj = nan([pic_size, 5]);
        curveCam = cell(size(curves));
        curveImg = cell(size(curves));
        for ci = 1:size(curves, 2)
            tangentProj{ci} = tangent_projection(curves{ci}, tangents{ci}, projMatrix);
            [K, RT] = Pdecomp(projMatrix);
            R = RT(1:3,1:3);
            T = RT(1:3, 4);
    
            cp = [curves{ci}'; ones(1, size(curves{ci}, 1))];
            cp = RT * cp;
            curveCam{ci} = cp';
    
            pointProj = K * cp;
            pointProj = pointProj(1:2, :) ./ pointProj(3, :);
            curveImg{ci} = pointProj';
    
            for pi = 1:size(pointProj, 2)
                r = floor(pointProj(2, pi) + 1);
                c = floor(pointProj(1, pi) + 1);
                if r >= 1 && r <= pic_size(1) && c >= 1 && c <= pic_size(2)
                    if isnan(curvesProj(r, c, 2)) || curvesProj(r, c, 2) > sqrt(sum(curveCam{ci}(pi, :).^2))
                        curvesProj(r, c, 1) = tangentProj{ci}(pi);
                        curvesProj(r, c, 2) = sqrt(sum(curveCam{ci}(pi, :).^2));
                        curvesProj(r, c, 3:5) = curves{ci}(pi, :);
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
                assert(abs(curvesProj(i, j, 2) - norm(dir)) < 1e-7)
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
    
        matchCurves_view{end + 1} = match;
        unmatchCurves_view{end + 1} = unmatch;
        curvesProj_view{end + 1} = curvesProj;
        % fileID = fopen(fullfile(pwd, 'tmp', 'optix', sprintf("view_%d.txt", viewCnt)),'w');
        % fprintf(fileID,'%d %d %f %f %f %f %f %f %f\n', match');
        % fclose(fileID);
        fprintf("Finished curve matching in view %d\n", viewCnt);
        viewCnt = viewCnt + 1;
    end
    save(fullfile(pwd,'tmp', 'curve_matches.mat'), "curvesProj_view", "matchCurves_view", "unmatchCurves_view", "edgeList_view", '-v7.3');
else
    var = load(fullfile(pwd,'tmp', 'curve_matches.mat'));
    curvesProj_view = var.curvesProj_view;
    matchCurves_view = var.matchCurves_view;
    unmatchCurves_view = var.unmatchCurves_view;
    edgeList_view = var.edgeList_view;
    viewCnt = size(curvesProj_view, 2);
end
toc;

if PARAMS.SAVE_MATCH_PLOT_2D == 1
    if ~exist(fullfile(pwd, 'tmp', 'figures'), 'dir')
        mkdir(fullfile(pwd, 'tmp', 'figures'))
    end
    f = figure('visible','off');
    for plotView = 1:viewCnt
        scatter(matchCurves_view{plotView}(:, 2), matchCurves_view{plotView}(:, 1),2,'red', 'filled')
        hold on;
        scatter(edgeList_view{plotView}(:, 1), (1200 * ones(size(edgeList_view{plotView}(:, 2)))) - edgeList_view{plotView}(:, 2),1,'green', 'filled')
        hold off;
        saveas(f,fullfile(pwd, 'tmp', 'figures', sprintf("matchCurves_view_%d", plotView - 1)),'jpg');
    end
    close(f)
end

if PARAMS.SHOW_PLOT_MATCH == 1
    plotView = PARAMS.PLOT_MATCH_VIEW;
    for i = 1:size(curves, 2)
        scatter3(curves{i}(:, 1), curves{i}(:, 2), curves{i}(:, 3), 1, 'green', 'filled');
        hold on;
    end

    cp = matchCurves_view{plotView}(:, 6:8) .*  [matchCurves_view{plotView}(:, 9) matchCurves_view{plotView}(:, 9) matchCurves_view{plotView}(:, 9)];
    cp = cp + matchCurves_view{plotView}(:, 3:5);
    scatter3(cp(:, 1), cp(:, 2), cp(:, 3), 3, 'red', 'filled')

    ccenter = matchCurves_view{plotView}(1, 3:5);
    scatter3(ccenter(1), ccenter(2), ccenter(3), 40, 'red', 'filled');
    text(ccenter(1), ccenter(2), ccenter(3),sprintf("%d", plotView));
    for k = 1:10
        idx = randi(size(cp, 1), 1, 1);
        ray = [ccenter; cp(idx, :)];
        plot3(ray(:, 1), ray(:, 2), ray(:, 3), 'Color','cyan');
    end
    hold off;
    figure;
    scatter(matchCurves_view{plotView}(:, 2), matchCurves_view{plotView}(:, 1),2,'red', 'filled')
    hold on;
    scatter(edgeList_view{plotView}(:, 1), (1200 * ones(size(edgeList_view{plotView}(:, 2)))) - edgeList_view{plotView}(:, 2),1,'green', 'filled')
    hold off;
end

if PARAMS.RAY_TRACING  == 1
    tic;
    surface_intersection_count = zeros(size(pairs, 1), 1);
    parfor i = 1:size(pairs, 1)
        tic;
        c1 = pairs(i, 1);
        c2 = pairs(i, 2);
    
        surfaceName = "loftsurf_" + int2str(pairs(i, 1)) + "_" + int2str(pairs(i, 2)) + "_";
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
    
        for v = 1:viewCnt
            for k = 1:size(matchCurves_view{v}, 1)
                ct = matchCurves_view{v}(k, 3:5);
                dir = matchCurves_view{v}(k, 6:8);
                dis = matchCurves_view{v}(k, 9);
                [intersect, t] = TriangleRayIntersection(ct, dir, pts(tri(:, 1), :), pts(tri(:, 2), :), pts(tri(:, 3), :), 'lineType' , 'ray');
                %> visualization
                % trimesh(tri, pts(:, 1), pts(:, 2), pts(:, 3))
                % hold on;
                % scatter3(ct(1), ct(2), ct(3), 40, 'red', 'filled');
                % ray = [ct; ct + dis .* dir];
                % plot3(ray(:, 1), ray(:, 2), ray(:, 3));
                % hold off;
                intersectPointIdx = find(intersect == 1);
                if isempty(intersectPointIdx)
                    continue;
                end
                diff =  dis - t(intersectPointIdx);
                if ~isempty(find(diff > 0.2))
                    surface_intersection_count(i) = surface_intersection_count(i) + 1;
                end
            end
        end
        fprintf("Finished %s\n", surfaceName);
        toc;
    end
    save(fullfile(pwd, 'tmp', 'surface_intersection_count.mat'), "surface_intersection_count");
    toc;
else
    surface_intersection_count = load(fullfile(pwd, 'tmp', 'surface_intersection_count.mat')).surface_intersection_count;
end

if PARAMS.SURFACE_FILTERING == 1
    if exist(fullfile(pwd, 'tmp', 'filterd_surfaces'), 'dir')
       rmdir((fullfile(pwd, 'tmp', 'filterd_surfaces')), 's')
    end
    mkdir(fullfile(pwd, 'tmp', 'filterd_surfaces'))
    cnt = 0;
    for i = 1:size(pairs, 1)
        if surface_intersection_count(i) > PARAMS.SURFACE_FILTERING_THRESHOLD
            continue;
        end
    
        c1 = pairs(i, 1);
        c2 = pairs(i, 2);
    
        surfaceName = "loftsurf_" + int2str(pairs(i, 1)) + "_" + int2str(pairs(i, 2)) + "_";
        if(pairs(i, 3) == 1)
            surfaceName = surfaceName + "normal.ply";
        else
            surfaceName = surfaceName + "reverse.ply";
        end
        
        copyfile(fullfile(pwd, 'blender', 'output', surfaceName), fullfile(pwd, 'tmp', 'filterd_surfaces', surfaceName))
        cnt = cnt + 1;
    end
    fprintf("Surface number after filtering: %d\n", cnt);
end

