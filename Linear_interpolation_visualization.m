close all;

addpath(fullfile(pwd, 'util'));
addpath(fullfile(pwd, 'util', 'plyread'));

% Standalone script, run on EVERY .ply surface in tmp/filtered_surfaces:
% 1) parses each surface's curve pair ids (loftsurf_<id1>_<id2>_*.ply -- the
%    same ids that proximity_paring.m produces in curves_proximity_pairs)
% 2) plots curve 1 and curve 2 of that pair
% 3) plots the ground-truth .obj as a solid white surface so you can see
%    where the two curves lie on it
% 4) plots the 2D edges / interpolation of the pair in VIEW_ID. The 2D points of
%    c1 / c2 are found like Cross_Rotation_point_validation.m: pipeline curve k
%    <-> GT curve_id k-1, then every GT sample of that curve with a 2D edge in
%    VIEW_ID (no 3D snapping)
% (3 figures per surface)

% ---- what to show ----
PARAMS.PLY_DIR  = fullfile(pwd, 'tmp', 'filtered_surfaces');   % every *.ply in here is processed
PARAMS.PLY_NAME = 'loftsurf_12_21_normal.ply';   % '' = run ALL .ply in PLY_DIR; otherwise only this one, e.g. 'loftsurf_12_34_xxx.ply'
                        % (.ply extension optional; a cell array of names or a wildcard such as 'loftsurf_12_34_*' also works)
PARAMS.GT_FILE  = fullfile(pwd, 'data', 'ABC-NEF', '00000325', ...
    '00000325_3062bccff48e47a2b9de05e3_trimesh_020.obj');
PARAMS.VIEW_ID  = 'all';   % 0-based view id for the 2D edge visualization: a single id, a vector (e.g. [3 10 20]),
                        % or 'all' for every view (0..n_views-1, 0-49 here)
PARAMS.CORRESP_JSON = fullfile(pwd, 'tools', 'GT_edge_corresp_ABC_NEF', 'GT_3D_2D_assoc_0325.json');
PARAMS.OBJECT_DIR   = fullfile(pwd, 'ABC-NEF', '00000325');
PARAMS.SHOW_GT_EDGE_OVERLAY = 1;  % 1 = overlay the GT 2D edges of VIEW_ID on the grid figure
PARAMS.GRID_CELL_SIZE = 5;  % pixels; grid overlay on the interpolation figure (0 = off)
PARAMS.INTERP_STEPS = 10;    % number of in-between curves between curve 1 and curve 2
PARAMS.SHOW_SURFACE = 1;   % 1 = also draw the lofted .ply surface
PARAMS.SHOW_3D_FIGURE = 0;     % 1 = Figure 1 (GT .obj + surface + curves, 3D)
PARAMS.SHOW_EDGE_FIGURE = 0;   % 1 = Figure 2 (2D edge points of the pair)

% ---- curves (same source proximity_paring.m uses) ----
inputCurves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;

% ---- ground-truth obj ----
if ~exist(PARAMS.GT_FILE, 'file')
    error('GT obj not found: %s', PARAMS.GT_FILE);
end
[gtV, gtF] = read_obj_mesh(PARAMS.GT_FILE);

% The curves / lofted surfaces live in the unit box [0,1]^3 while the raw .obj
% is in [0,100]^3. Apply the same normalization the evaluation uses
% (evaluation/eval_surfaces_main.py: normalize_to_unit_box).
gtCenter = (min(gtV, [], 1) + max(gtV, [], 1)) / 2;
gtScale = max(max(gtV, [], 1) - min(gtV, [], 1));
gtV = (gtV - gtCenter) / gtScale + 0.5;

% ---- GT 2D edge points of VIEW_ID (shared by all surfaces) ----
% (lookup built by tools/GT_edge_corresp_construction.py)
% Pipeline curve k (1-based) <-> GT curve_id k-1 (0-based).
corr = jsondecode(fileread(PARAMS.CORRESP_JSON));
gtCurveId = corr.curve_id(:);
if (ischar(PARAMS.VIEW_ID) || isstring(PARAMS.VIEW_ID)) && strcmpi(PARAMS.VIEW_ID, 'all')
    viewIds = 0:corr.n_views - 1;
else
    viewIds = PARAMS.VIEW_ID(:)';
end
if any(viewIds < 0 | viewIds >= corr.n_views)
    error('VIEW_ID out of range (0..%d).', corr.n_views - 1);
end
assocViews = arrayfun(@(a) a.view, corr.associations);

imgSize = 800;

% ---- all surfaces ----
if isempty(PARAMS.PLY_NAME)
    plyFiles = dir(fullfile(PARAMS.PLY_DIR, '*.ply'));
else
    names = cellstr(PARAMS.PLY_NAME);
    plyFiles = [];
    for n = 1:numel(names)
        nm = names{n};
        if ~endsWith(nm, '.ply')
            nm = [nm '.ply']; %#ok<AGROW>
        end
        found = dir(fullfile(PARAMS.PLY_DIR, nm));
        if isempty(found)
            warning('No .ply matching "%s" in %s.', nm, PARAMS.PLY_DIR);
        end
        plyFiles = [plyFiles; found]; %#ok<AGROW>
    end
end
if isempty(plyFiles)
    error('No .ply surfaces found in %s (PLY_NAME = "%s")', PARAMS.PLY_DIR, strjoin(cellstr(PARAMS.PLY_NAME), ', '));
end
nSurf = numel(plyFiles);
fprintf('Processing %d surfaces x %d views from %s\n', nSurf, numel(viewIds), PARAMS.PLY_DIR);

for viewId = viewIds
PARAMS.VIEW_ID = viewId;   % the figure code below reads the current view from here
fprintf('\n########## VIEW %d ##########\n', viewId);

% GT 2D edge points of this view
blk = corr.associations(assocViews == viewId);
if isempty(blk.point_index)
    ptIdx = zeros(0, 1);
    edgePts = zeros(0, 3);
else
    ptIdx = blk.point_index(:);               % 1-based GT 3D sample index
    edgePts = reshape(blk.edge_points, [], 3); % x, y, theta
end

% GT 2D edges of this view (GT_edge_corresp_construction.py), one per
% unique detected edgel.
if isempty(blk.edgel_index)
    viewEdges = zeros(0, 3);
else
    viewEdges = reshape(blk.edge_points, [], 3);
    [~, ue] = unique(blk.edgel_index(:));
    viewEdges = viewEdges(sort(ue), :);
end

for s = 1:nSurf
    plyName = plyFiles(s).name;
    plyPath = fullfile(plyFiles(s).folder, plyName);
    fprintf('\n===== [%d/%d] %s =====\n', s, nSurf, plyName);

    % ---- curve pair ids from the .ply name ----
    tok = regexp(plyName, '^loftsurf_(\d+)_(\d+)', 'tokens', 'once');
    if isempty(tok)
        warning('Cannot parse curve pair ids from "%s" (expected loftsurf_<i>_<j>_*.ply); skipping.', plyName);
        continue;
    end
    pairId = [str2double(tok{1}), str2double(tok{2})];
    fprintf('Surface %s -> curve pair (%d, %d)\n', plyName, pairId(1), pairId(2));

    if any(pairId < 1) || any(pairId > numel(inputCurves))
        warning('Pair (%d, %d) out of range (%d curves); skipping.', pairId(1), pairId(2), numel(inputCurves));
        continue;
    end
    curve1 = inputCurves{pairId(1)};
    curve2 = inputCurves{pairId(2)};

    % ---- display (Figure 1, toggle: SHOW_3D_FIGURE) ----
    if PARAMS.SHOW_3D_FIGURE == 1
        fig = figure('Name', sprintf('%s - curve pair (%d, %d)', plyName, pairId(1), pairId(2)), ...
                     'NumberTitle', 'off', 'Color', [0.85 0.85 0.85]);
        ax = axes(fig);
        hold(ax, 'on');

        patch(ax, 'Faces', gtF, 'Vertices', gtV, 'FaceColor', [1 1 1], 'EdgeColor', 'none', ...
              'FaceLighting', 'gouraud', 'AmbientStrength', 0.5, 'DiffuseStrength', 0.7, ...
              'DisplayName', 'GT .obj');

        if PARAMS.SHOW_SURFACE == 1
            [tri, pts] = plyread(plyPath, 'tri');
            hSurf = patch(ax, 'Faces', tri, 'Vertices', pts, 'FaceColor', [1 0.55 0], 'FaceAlpha', 0.85, ...
                  'EdgeColor', 'none', 'DisplayName', sprintf('Surface %s', plyName));
        end

        h1 = plot3(ax, curve1(:, 1), curve1(:, 2), curve1(:, 3), '-', 'Color', [1 0 0], 'LineWidth', 3, ...
                   'DisplayName', sprintf('Curve 1 (id %d)', pairId(1)));
        h2 = plot3(ax, curve2(:, 1), curve2(:, 2), curve2(:, 3), '-', 'Color', [0 0.3 1], 'LineWidth', 3, ...
                   'DisplayName', sprintf('Curve 2 (id %d)', pairId(2)));

        axis(ax, 'equal');
        axis(ax, 'vis3d');
        set(ax, 'XGrid', 'on', 'YGrid', 'on', 'ZGrid', 'on');  % not grid(): a workspace variable named grid would shadow it
        view(ax, 3);
        camlight(ax, 'headlight');
        lighting(ax, 'gouraud');
        xlabel(ax, 'X'); ylabel(ax, 'Y'); zlabel(ax, 'Z');
        title(ax, sprintf('%s: curve pair (%d, %d) on GT', plyName, pairId(1), pairId(2)), ...
              'Interpreter', 'none');
        legendHandles = [h1, h2];
        if PARAMS.SHOW_SURFACE == 1
            legendHandles(end + 1) = hSurf;
        end
        legend(ax, legendHandles, 'Location', 'best', 'Interpreter', 'none');
        hold(ax, 'off');

        % ---- interactivity: drag to rotate, scroll to zoom, light follows camera ----
        hLight = findobj(ax, 'Type', 'light');
        rot = rotate3d(fig);
        rot.Enable = 'on';
        rot.ActionPostCallback = @(~, ~) camlight(hLight(1), 'headlight');
    end

    % ======================================================================
    % Figure 2: GT 2D edge points associated with curve 1 / curve 2 in one view
    % ======================================================================
    % c1 / c2 2D points as in Cross_Rotation_point_validation.m: pipeline curve k
    % <-> GT curve_id k-1; keep every GT sample of that curve that has a 2D edge
    % point in this view.
    curveSel = {pairId(1) - 1, pairId(2) - 1};
    edgeSets = cell(1, 2);
    for c = 1:2
        mask = gtCurveId(ptIdx) == curveSel{c};
        edgeSets{c} = edgePts(mask, :);
        fprintf('View %d, curve %d (GT id %d): %d 3D samples -> %d 2D edge points (of %d samples)', ...
                PARAMS.VIEW_ID, pairId(c), curveSel{c}, nnz(mask), size(edgeSets{c}, 1), nnz(gtCurveId == curveSel{c}));
    end

    e1 = edgeSets{1};
    e2 = edgeSets{2};

    % toggle: SHOW_EDGE_FIGURE
    if PARAMS.SHOW_EDGE_FIGURE == 1
        fig2 = figure('Name', sprintf('2D edges - view %d - curve pair (%d, %d)', PARAMS.VIEW_ID, pairId(1), pairId(2)), ...
                      'NumberTitle', 'off');
        ax2 = axes(fig2);
        hold(ax2, 'on');

        h21 = scatter(ax2, e1(:, 1), e1(:, 2), 14, [1 0 0], 'filled', ...
                      'DisplayName', sprintf('Curve 1 (id %d): %d pts', pairId(1), size(e1, 1)));
        h22 = scatter(ax2, e2(:, 1), e2(:, 2), 14, [0 0.3 1], 'filled', ...
                      'DisplayName', sprintf('Curve 2 (id %d): %d pts', pairId(2), size(e2, 1)));

        axis(ax2, 'equal');
        xlim(ax2, [0 imgSize - 1]);
        ylim(ax2, [0 imgSize - 1]);
        set(ax2, 'YDir', 'reverse');
        title(ax2, sprintf('View %d: 2D edge points of curve pair (%d, %d)', PARAMS.VIEW_ID, pairId(1), pairId(2)));
        legend(ax2, [h21, h22], 'Location', 'southoutside', 'Orientation', 'horizontal');
        hold(ax2, 'off');
    end

    % ======================================================================
    % Figure 3: linear interpolation between curve 1 and curve 2 (2D, this view)
    % Both 2D point sets are ordered along the curve (3D sample order),
    % paired by normalized arc length, aligned in direction, and blended:
    %   P(t) = (1 - t) * curve1(s) + t * curve2(s),  t in [0, 1]
    % ======================================================================
    A = order_curve_points(e1(:, 1:2));
    B = order_curve_points(e2(:, 1:2));
    if size(A, 1) < 2 || size(B, 1) < 2
        warning('Need >= 2 edge points on both curves in view %d (curve 1: %d, curve 2: %d); skipping interpolation.', ...
                PARAMS.VIEW_ID, size(A, 1), size(B, 1));
    else
        % Pair points by normalized arc length. The curve with more edge points is
        % kept as-is (real detected points); the other is sampled at the same
        % arc-length positions.
        if size(A, 1) >= size(B, 1)
            B = sample_polyline_at(B, arclength_fractions(A));
        else
            A = sample_polyline_at(A, arclength_fractions(B));
        end
        % align direction: flip curve 2 if that makes the rungs shorter
        if norm(A(1, :) - B(end, :)) + norm(A(end, :) - B(1, :)) < ...
           norm(A(1, :) - B(1, :)) + norm(A(end, :) - B(end, :))
            B = flipud(B);
        end

        fig3 = figure('Name', sprintf('2D interpolation - view %d - curve pair (%d, %d)', PARAMS.VIEW_ID, pairId(1), pairId(2)), ...
                      'NumberTitle', 'off');
        ax3 = axes(fig3);
        hold(ax3, 'on');

        litEdges = zeros(0, 3);

        % Highlight every grid cell covered by the interpolated region. The
        % region is sampled densely (several samples per cell along each rung
        % and between rungs) and each sample is looked up with
        % arbitarary_edge_to_Grid_assocication (edge point -> grid cell).
        if PARAMS.GRID_CELL_SIZE > 0
            nAlong = max(2, ceil(max(sqrt(sum((A - B).^2, 2))) / (PARAMS.GRID_CELL_SIZE / 4)) + 1);
            tDense = linspace(0, 1, nAlong);
            regionPts = zeros(0, 2);
            for k = 1:size(A, 1)
                regionPts = [regionPts; (1 - tDense') * A(k, :) + tDense' * B(k, :)]; %#ok<AGROW>
            end
            [regionIds, regionCol, regionRow, gridInfo] = ...
                arbitarary_edge_to_Grid_assocication(regionPts, PARAMS.GRID_CELL_SIZE, imgSize);
            [coveredIds, firstIdx] = unique(regionIds(~isnan(regionIds)));
            validIdx = find(~isnan(regionIds));
            firstIdx = validIdx(firstIdx);
            cw = gridInfo.cellSize;
            x0 = regionCol(firstIdx) * cw;
            y0 = regionRow(firstIdx) * cw;
            patch(ax3, [x0, x0 + cw, x0 + cw, x0]', [y0, y0, y0 + cw, y0 + cw]', 'w', ...
                  'FaceColor', 'none', 'EdgeColor', [0 0.7 0], 'LineWidth', 1.5, 'HandleVisibility', 'off');
            fprintf('Interpolated region covers %d grid cells (%d px cells)\n', numel(coveredIds), cw);

            % grid ids -> the GT 2D edges lying inside those lit cells
            % (a non-empty `edges` argument is used as-is, so pass viewEdges
            % only when it has points; otherwise there is nothing to light)
            if ~isempty(viewEdges)
                [~, ~, litCount, ~, ~, litEdges] = grid_to_2D_edge_assocication( ...
                    coveredIds, viewEdges, PARAMS.GRID_CELL_SIZE, imgSize, PARAMS.VIEW_ID, false);
                fprintf('Lit cells contain %d GT 2D edge points (%d cells with edges)\n', ...
                        size(litEdges, 1), nnz(litCount > 0));
            end
        end

        % thin gray grid every GRID_CELL_SIZE pixels in x and y
        if PARAMS.GRID_CELL_SIZE > 0
            gridLines = 0:PARAMS.GRID_CELL_SIZE:imgSize - 1;
            nG = numel(gridLines);
            plot(ax3, [gridLines; gridLines], repmat([0; imgSize - 1], 1, nG), '-', ...
                 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5, 'HandleVisibility', 'off');
            plot(ax3, repmat([0; imgSize - 1], 1, nG), [gridLines; gridLines], '-', ...
                 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5, 'HandleVisibility', 'off');
        end

        % all GT 2D edges of this view, gray (toggle: SHOW_GT_EDGE_OVERLAY)
        legendHandles3 = [];
        if PARAMS.SHOW_GT_EDGE_OVERLAY == 1
            hAll = scatter(ax3, viewEdges(:, 1), viewEdges(:, 2), 6, [0.35 0.35 0.35], 'filled', ...
                           'DisplayName', sprintf('GT 2D edges, view %d', PARAMS.VIEW_ID));
            legendHandles3 = hAll;
        end

        % any other GT 2D edge inside the covered grid cells (not c1 / c2): purple
        if ~isempty(litEdges)
            onPair = ismember(litEdges(:, 1:2), [e1(:, 1:2); e2(:, 1:2)], 'rows');
            litOut = litEdges(~onPair, :);
            hLitOut = scatter(ax3, litOut(:, 1), litOut(:, 2), 24, [0.55 0 0.8], 'filled', ...
                              'MarkerEdgeColor', 'k', 'LineWidth', 0.5, ...
                              'DisplayName', sprintf('Other edge points: %d', size(litOut, 1)));
            legendHandles3 = [legendHandles3, hLitOut];
        end

        % curve 1 = blue, curve 2 = red, drawn on top
        h31 = scatter(ax3, A(:, 1), A(:, 2), 22, [0 0.3 1], 'filled', ...
                      'DisplayName', sprintf('Curve 1 (id %d) edge points', pairId(1)));
        h32 = scatter(ax3, B(:, 1), B(:, 2), 22, [1 0 0], 'filled', ...
                      'DisplayName', sprintf('Curve 2 (id %d) edge points', pairId(2)));
        legendHandles3 = [h31, h32, legendHandles3];

        axis(ax3, 'equal');
        xlim(ax3, [0 imgSize - 1]);
        ylim(ax3, [0 imgSize - 1]);
        set(ax3, 'YDir', 'reverse');
        title(ax3, sprintf('View %d: curve %d (blue) and curve %d (red)', ...
              PARAMS.VIEW_ID, pairId(1), pairId(2)));
        legend(ax3, legendHandles3, 'Location', 'southoutside', 'Orientation', 'horizontal');
        hold(ax3, 'off');
    end
end
end

function P = order_curve_points(P)
%ORDER_CURVE_POINTS Drop consecutive duplicate points (several 3D samples can
% share one detected 2D edge point), keeping the sample order along the curve.
if size(P, 1) < 2
    return;
end
keep = [true; any(abs(diff(P, 1, 1)) > 1e-9, 2)];
P = P(keep, :);
end

function f = arclength_fractions(P)
%ARCLENGTH_FRACTIONS Normalized cumulative arc length (0..1) at each polyline vertex.
s = [0; cumsum(sqrt(sum(diff(P, 1, 1).^2, 2)))];
if s(end) < 1e-12
    f = linspace(0, 1, size(P, 1))';
else
    f = s / s(end);
end
end

function Q = sample_polyline_at(P, f)
%SAMPLE_POLYLINE_AT Points on polyline P at normalized arc-length positions f.
s = [0; cumsum(sqrt(sum(diff(P, 1, 1).^2, 2)))];
if s(end) < 1e-12
    Q = repmat(P(1, :), numel(f), 1);
    return;
end
sq = f(:) * s(end);
Q = [interp1(s, P(:, 1), sq, 'linear'), interp1(s, P(:, 2), sq, 'linear')];
end

function [V, F] = read_obj_mesh(path)
%READ_OBJ_MESH Minimal Wavefront .obj reader (vertices + polygon faces -> triangles).
lines = splitlines(string(fileread(path)));

vLines = extractAfter(lines(startsWith(lines, "v ")), 2);
V = sscanf(strjoin(vLines, newline), '%f', [3 Inf])';

fLines = extractAfter(lines(startsWith(lines, "f ")), 2);
fLines = regexprep(fLines, '/\S*', '');          % drop /vt/vn
isTri = all(cellfun(@(c) numel(strsplit(strtrim(c))) == 3, cellstr(fLines(1:min(end, 50)))));
if isTri
    F = sscanf(strjoin(fLines, newline), '%d', [3 Inf])';
else
    F = zeros(0, 3);
    for i = 1:numel(fLines)
        idx = sscanf(char(fLines(i)), '%d')';
        for k = 2:numel(idx) - 1                  % fan-triangulate
            F(end + 1, :) = [idx(1), idx(k), idx(k + 1)]; %#ok<AGROW>
        end
    end
end
F(F < 0) = F(F < 0) + size(V, 1) + 1;            % negative = relative index
end
