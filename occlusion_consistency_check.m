clear;
close all;

addpath(fullfile(pwd, 'util'));
addpath(fullfile(pwd, 'util', 'TriangleRayIntersection'));
addpath(fullfile(pwd, 'util', 'plyread/'));

PARAMS.TAU_ORIENTATION                     = 16; %> pi/n pi/16 in this case
PARAMS.TAU_DISTANCE                        = 5; %> 5 pixels

if ~exist(fullfile(pwd, 'tmp', 'image'), 'dir')
   mkdir(fullfile(pwd, 'tmp', 'image'))
end
if ~exist(fullfile(pwd, 'tmp', 'res'), 'dir')
   mkdir(fullfile(pwd, 'tmp', 'res'))
end

orientation_bin_positive = linspace(0, 1, PARAMS.TAU_ORIENTATION + 1);
orientation_bin_negtative = linspace(-1, 0, PARAMS.TAU_ORIENTATION + 1);

[pixel_offset_col,pixel_offset_row] = meshgrid(-PARAMS.TAU_DISTANCE:PARAMS.TAU_DISTANCE,-PARAMS.TAU_DISTANCE:PARAMS.TAU_DISTANCE);
pixel_offset_row = reshape(pixel_offset_row, [], 1);
pixel_offset_col = reshape(pixel_offset_col, [], 1);

view = 0;
% load pairs
pairs = load("./tmp/pairs_after_curvature_filter.mat").pairs_after_curvature_filter;

% load curves
curves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;

% load tangents
tangents = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.tangents;

while true
    tic;
    fname1 = fullfile(pwd, 'data','amsterdam-house-full', sprintf("%02d.projmatrix", view));
    fname2 = fullfile(pwd, 'data', 'TO_Edges_Amsterdam_House', sprintf("%02d.mat", view));
    fname3 = fullfile(pwd, 'data', 'amsterdam-house-full', sprintf( "%02d.jpg", view ));
    try
        projMatrix = load(fname1);
        edge = load(fname2).TO_edges;
        pic_size = size(imread(fname3), 1:2);
    catch
        break;
    end
    

    edge_bucket = zeros([pic_size PARAMS.TAU_ORIENTATION]);
    for i = 1:size(edge, 1)
        r = floor(edge(i, 2) + 1);
        c = floor(edge(i, 1) + 1);
        o = - 1;
        if edge(i, 3) >= 0
            o = find(orientation_bin_positive <= min(edge(i, 3), pi - eps) / pi, 1, 'last');
        else
            o = find(orientation_bin_negtative <= max(edge(i, 3), - pi + eps) / pi, 1, 'last');
        end
        assert(o >= 1 && o <= PARAMS.TAU_ORIENTATION);
        assert((edge(i, 3) >= 0 && edge(i, 3) >= orientation_bin_positive(o) * pi && edge(i, 3) < orientation_bin_positive(o + 1) * pi)...
        || (edge(i, 3) < 0 && edge(i, 3) >= orientation_bin_negtative(o) * pi && edge(i, 3) < orientation_bin_negtative(o + 1) * pi))
        for k = 1:size(pixel_offset_col, 1)
            nr = r + pixel_offset_row(k);
            nc = c + pixel_offset_col(k);
            if nr < 1 || nr > pic_size(1) || nc < 1 || nc > pic_size(2)
                continue;
            end
            edge_bucket(nr, nc, o) = 1;
        end
    end

    tangentProj = cell(size(tangents));
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
        pointProj = pointProj(1:2, :) ./ pointProj(3);
        curveImg{ci} = pointProj';
    end
    res = {};
    evidence_by_view = {};
    parfor i = 1:size(pairs, 1)
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

        match_matrix = -1 * int8(ones(size(edge_bucket, 1:2)));
        [K, RT] = Pdecomp(projMatrix);
        R = RT(1:3,1:3);
        T = RT(1:3, 4);
        vertices = [pts'; ones(1, size(pts, 1))];
        vertices = RT * vertices;
        evidence = [0 0];
        for cIdx = 1:size(curves, 2)
            if cIdx == c1 || cIdx == c2
                continue;
            end
            for p = 1:size(curveCam{cIdx}, 1)
                point = curveCam{cIdx}(p, :);
                vert1 = vertices(:, tri(:,1));
                vert2 = vertices(:, tri(:,2));
                vert3 = vertices(:, tri(:,3));
                [intersect] = TriangleRayIntersection([0 0 0], point, vert1, vert2, vert3, 'lineType' , 'segment');
                intersectPointIdx = find(intersect == 1);
                if isempty(intersectPointIdx)
                    continue;
                end
                r = floor(curveImg{cIdx}(p, 2) + 1);
                c = floor(curveImg{cIdx}(p, 1) + 1);
                o = - 1;
                t = tangentProj{cIdx}(p);
                if t >= 0
                    o = find(orientation_bin_positive <= min(t, pi - eps) / pi, 1, 'last');
                else
                    o = find(orientation_bin_negtative <= max(t, - pi + eps) / pi, 1, 'last');
                end
                assert(o >= 1 && o <= PARAMS.TAU_ORIENTATION);
                if edge_bucket(r, c, o) ~= 0
                    match_matrix(r, c) = 1;
                    evidence = evidence + 1;
                else
                    match_matrix(r, c) = 0;
                    evidence(2) = evidence(2) + 1;
                end
            end
        end
        res{i} = int8(match_matrix);
        evidence_by_view{i} = evidence;
        visual = [];
        % red match
        visual(:, :, 1) = double(match_matrix == 1);
        % green edge map
        visual(:, :, 2) = double((sum(edge_bucket, 3) ~= 0));
        % blue no-match
        visual(:, :, 3) = double(match_matrix == 0);
        visual = double(visual);
        visual(:, :, 2) = visual(:, :, 2) * 0.1;
        % imshow(double(visual));
        imwrite(double(visual), fullfile(pwd, 'tmp', 'image', sprintf("surface %d view %d.jpg", i, view)));
    end
    save(fullfile(pwd,'tmp', 'res', sprintf("view %d", view)), 'res');
    save(fullfile(pwd,'tmp', 'res', sprintf("evidence in view %d", view)), 'evidence_by_view');
    view = view + 1;
    toc;
end