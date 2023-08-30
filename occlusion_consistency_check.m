clear;
addpath("./util/TriangleRayIntersection/");
addpath("./util/plyread");
addpath("./util/");

if ~exist(fullfile(pwd, 'tmp', 'image'), 'dir')
   mkdir(fullfile(pwd, 'tmp', 'image'))
end

% load projmatrix and edge
projMatrix = {};
edgeMaps = {};
cnt = 0;
while true
   fname1 = sprintf( "./data/amsterdam-house-full/%02d.projmatrix", cnt );
   fname2 = sprintf( "./data/TO_Edges_Amsterdam_House/%02d.mat", cnt );
   fname3 = sprintf( "./data/amsterdam-house-full/%02d.jpg", cnt );
   try
        edge = load(fname2).TO_edges;
        pic = imread(fname3);
        map = zeros(size(pic, 1), size(pic, 2));
        for i = 1:size(edge, 1)
            pos_x = floor(edge(i, 1) + 1);
            pos_y = floor(edge(i, 2) + 1);
            map(pos_y, pos_x) = 1;
        end

        edgeMaps{end + 1} = map;
        projMatrix{end + 1} = load(fname1);
   catch
       break;
   end
   cnt = cnt + 1;
end

viewCnt = size(projMatrix, 2);

% load pairs
pairs = load("./tmp/pairs_after_curvature_filter.mat").pairs_after_curvature_filter;

% load curves
curves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;

kernel = ones(7, 7);


res = [];
res_per_view = {};
tic
parfor i = 1:size(pairs, 1)
    c1 = pairs(i, 1);
    c2 = pairs(i, 2);
    surfaceName = "./blender/output/" + "loftsurf_" + int2str(pairs(i, 1)) + "_" + int2str(pairs(i, 2)) + "_";
    if(pairs(i, 3) == 1)
        surfaceName = surfaceName + "normal.ply";
    else
        surfaceName = surfaceName + "reverse.ply";
    end
    disp(surfaceName);
    % surfaceName = "./blender/loftsurf_19_32_reverse.ply";
    try
        [tri,pts] = plyread(surfaceName,'tri');
    catch
        continue;
    end
    proof = [];
    tic
    for view = 1:viewCnt
        [K, RT] = Pdecomp(projMatrix{view});
        R = RT(1:3,1:3);
        T = RT(1:3, 4);
        edgeMapConv = conv2(edgeMaps{view}, kernel, 'same');
        curveProjMap = zeros(size(edgeMapConv));
        vertices = [pts'; ones(1, size(pts, 1))];
        vertices = RT * vertices;
        for cIdx = 1:size(curves, 2)
            if cIdx == c1 || cIdx == c2
                continue;
            end
            curve = curves{cIdx}';
            curve = [curve; ones(1, size(curve, 2))];
            curve_cam = RT * curve;

            for p = 1:size(curve_cam, 2)
                point = curve_cam(:, p);
                vert1 = vertices(:, tri(:,1));
                vert2 = vertices(:, tri(:,2));
                vert3 = vertices(:, tri(:,3));
                [intersect] = TriangleRayIntersection([0 0 0], point, vert1, vert2, vert3, 'lineType' , 'segment');
                intersectPointIdx = find(intersect == 1);
                if isempty(intersectPointIdx)
                    continue;
                end
                pointProj = K * point;
                pointProj = pointProj ./ pointProj(3);
                pos_x = floor(pointProj(1) + 1);
                pos_y = floor(pointProj(2) + 1);
                if pos_x < 1 || pos_x > 1600 || pos_y < 1 || pos_y > 1200
                    continue;
                end
                curveProjMap(pos_y, pos_x) = 1;
            end
        end
        % diff1 = conv2(edgeMapConv, [0 0 0; 1 1 1; 0 0 0], 'same') & conv2(curveProjMap, [0 0 0; 1 1 1; 0 0 0], 'same');
        % diff2 = conv2(edgeMapConv, [0 1 0; 0 1 0; 0 1 0], 'same') & conv2(curveProjMap, [0 1 0; 0 1 0; 0 1 0], 'same');
        % diff3 = conv2(edgeMapConv, [1 0 0; 0 1 0; 0 0 1], 'same') & conv2(curveProjMap, [1 0 0; 0 1 0; 0 0 1], 'same');
        % diff4 = conv2(edgeMapConv, [0 0 1; 0 1 0; 1 0 0], 'same') & conv2(curveProjMap, [0 0 1; 0 1 0; 1 0 0], 'same');
        % disp(sum([diff1 diff2 diff3 diff4], 'all'));
        % diff1 = (~conv2(edgeMapConv, [0 0 0; 1 1 1; 0 0 0], 'same')) & conv2(curveProjMap, [0 0 0; 1 1 1; 0 0 0], 'same');
        % diff2 = (~conv2(edgeMapConv, [0 1 0; 0 1 0; 0 1 0], 'same')) & conv2(curveProjMap, [0 1 0; 0 1 0; 0 1 0], 'same');
        % diff3 = (~conv2(edgeMapConv, [1 0 0; 0 1 0; 0 0 1], 'same')) & conv2(curveProjMap, [1 0 0; 0 1 0; 0 0 1], 'same');
        % diff4 = (~conv2(edgeMapConv, [0 0 1; 0 1 0; 1 0 0], 'same')) & conv2(curveProjMap, [0 0 1; 0 1 0; 1 0 0], 'same');
        % disp(sum([diff1 diff2 diff3 diff4], 'all'));
        overlay = curveProjMap;
        overlay(:, :, 2) = (edgeMapConv & ones(size(edgeMapConv))) * 0.1;
        overlay(:, :, 3) = edgeMapConv & curveProjMap;
        % imshow(double(overlay));
        imgName = fullfile(pwd, 'tmp', 'image', "surface_" + int2str(i) + "_view_" + int2str(view) + ".jpg");
        imwrite(double(overlay), imgName);
        diff = edgeMapConv & curveProjMap;
        proof = [proof; sum(diff, 'all') sum(curveProjMap, 'all')];
        % subplot(1, 3, 1);
        % imshow(double(edgeMapConv));
        % subplot(1, 3, 2);
        % imshow(double(curveProjMap));
        % subplot(1, 3, 3);
        % imshow(double(diff));
        %%%%%%
        % break;
    end
    toc
    %%%%%
    % break;
    disp([i sum(proof) surfaceName]);
    res(i, :) = [i sum(proof) surfaceName];
    res_per_view{i} = proof;
end
toc
save("./tmp/res.mat", "res");
save("./tmp/res_per_view.mat", "res_per_view");
selected = find(4 * res(:, 2) <= res(:, 3));
if ~exist("./blender/res/", 'dir')
   mkdir("./blender/res/")
end
for i = 1:size(selected, 1)
    surfaceName = "./blender/output/" + "loftsurf_" + int2str(pairs(selected(i), 1)) + "_" + int2str(pairs(selected(i), 2)) + "_";
    if(pairs(selected(i), 3) == 1)
        surfaceName = surfaceName + "normal.ply";
    else
        surfaceName = surfaceName + "reverse.ply";
    end
    copyfile(surfaceName, "./blender/res/")
end

% gc = min(abs(res(:, [3 4])), [], 2);
% histogram(gc, "NumBins",10)
% histogram(v, "NumBins",10, "EdgeColor","red");
