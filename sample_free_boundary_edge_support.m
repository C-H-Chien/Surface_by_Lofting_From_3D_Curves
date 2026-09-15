close all;

addpath(fullfile(pwd, 'util'));
addpath(fullfile(pwd, 'util', 'plyread'));

% Standalone script:
% 1) loads ONE .ply mesh (by name) from blender/output
% 2) samples boundary points + 3D tangents on that mesh (the whole loop)
%    and labels every point "curve1" / "curve2" / "free"
%    -- identical sampling/labeling logic to sample_surface_boundaries.m
% 3) keeps only the boundary points labeled "free"
% 4) prompts for a camera view (or 0 to render every view) and, for each
%    selected view:
%    a) projects the free-boundary points+tangents to that camera view
%    b) loads the detected 2D third-order edges for that view and buckets
%       them once into a uniform pixel grid (coarse-to-fine spatial
%       partition) -- this is the SAME grid drawn in the visualization
%    c) for each projected free-boundary point, only compares against 2D
%       edges in its own grid cell + the 8 neighboring cells (instead of
%       all N edges), and marks the point "supported" if a nearby edge
%       also matches in orientation
%       -- identical grid/support logic to visualize_boundary_edge_support.m
%    d) displays the grid, the 2D edges (green), and the free-boundary
%       points colored by support status (blue = supported, red = unsupported)

% ---- what to show ----
PARAMS.MESH_NAME = 'loftsurf_18_21_normal.ply'; % mesh file inside blender/output

% ---- sampling ----
PARAMS.MESH_DIR = fullfile(pwd, 'blender', 'output');
PARAMS.SAMPLES_PER_SURFACE = 300;
PARAMS.BOUNDARY_ASSIGNMENT_TOL = []; % manual curve-assignment tolerance, or [] to derive from curve spacing

% ---- projection / image plane ----
PARAMS.DATASET_NAME = 'ABC-NEF';
PARAMS.SCENE_NAME = '00000325';
PARAMS.PLANE_ROWS = 800;
PARAMS.PLANE_COLS = 800;
PARAMS.DRAW_ONLY_IN_IMAGE_BOUNDS = 1;

% ---- coarse-to-fine edge-support check ----
PARAMS.GRID_CELL_SIZE = 30;      % pixels per grid cell used to bucket 2D edges
PARAMS.TAU_DISTANCE = 3;         % pixels; max distance to a candidate 2D edge to count as support
PARAMS.TAU_ORIENTATION_DEG = 10;  % degrees; max orientation difference (mod 180) to count as support

% ---- display / output ----
PARAMS.SHOW_GRID = 1;
PARAMS.SAVE_FIGURE = 1;
PARAMS.SAVE_SAMPLES = 1;

meshPath = fullfile(PARAMS.MESH_DIR, char(PARAMS.MESH_NAME));
if ~exist(meshPath, 'file')
    error('Mesh not found: %s', meshPath);
end

% ---- projection matrices (needed up front to know how many views exist) ----
projDir = fullfile(pwd, 'data', PARAMS.DATASET_NAME, PARAMS.SCENE_NAME, 'projection_matrix');
projMatrixByView = load_projection_matrices(projDir);
if isempty(projMatrixByView)
    error('No projection matrices found in: %s', projDir);
end
numViews = numel(projMatrixByView); % views are 0-based (view 0 .. numViews-1) in file names

% ---- input curves, needed to know which boundary samples are "curve1"/"curve2"/"free" ----
curve1 = [];
curve2 = [];
preProcessedFile = fullfile(pwd, 'tmp', 'preProcessedCurves.mat');
if exist(preProcessedFile, 'file')
    preProcessed = load(preProcessedFile);
    inputCurves = preProcessed.preProcessedCurves.points;
    curveIds = parse_surface_curve_ids(PARAMS.MESH_NAME);
    if numel(curveIds) == 2
        c1 = curveIds(1);
        c2 = curveIds(2);
        if c1 >= 1 && c1 <= numel(inputCurves) && c2 >= 1 && c2 <= numel(inputCurves)
            curve1 = inputCurves{c1};
            curve2 = inputCurves{c2};
        end
    end
else
    fprintf('Warning: %s not found; all boundary points will be labeled "free".\n', preProcessedFile);
end

% ---- sample the mesh boundary (ordered loop) + labels (view-independent) ----
fprintf('Sampling boundary of %s ...\n', PARAMS.MESH_NAME);
[tri, pts] = plyread(meshPath, 'tri');
[sampledPts, ~, labels] = sample_mesh_boundary_points(pts, tri, ...
    PARAMS.SAMPLES_PER_SURFACE, curve1, curve2, PARAMS.BOUNDARY_ASSIGNMENT_TOL);
if isempty(sampledPts)
    error('No boundary points sampled from %s', PARAMS.MESH_NAME);
end
fprintf('  sampled %d boundary points (curve1: %d, curve2: %d, free: %d)\n', ...
    size(sampledPts, 1), sum(labels == "curve1"), sum(labels == "curve2"), sum(labels == "free"));

% ---- 3D tangent at every sampled point, using the full ordered loop ----
worldTangents = compute_world_tangents(sampledPts);

% ---- keep only the free-boundary points ----
isFree = labels == "free";
freePts = sampledPts(isFree, :);
freeTangents = worldTangents(isFree, :);
if isempty(freePts)
    error('No "free" boundary points found on %s', PARAMS.MESH_NAME);
end
fprintf('  %d free-boundary points to evaluate\n', size(freePts, 1));

% ---- prompt for which view(s) to render ----
promptMsg = sprintf('Enter view index (0-%d) to render one view, or "all" to render ALL %d views: ', ...
    numViews - 1, numViews);
viewInput = strtrim(input(promptMsg, 's'));

if strcmpi(viewInput, 'all')
    fprintf('Rendering all %d views into one figure...\n', numViews);
    nCols = ceil(sqrt(numViews));
    nRows = ceil(numViews / nCols);

    fig = figure('Name', sprintf('%s - all views - free boundary edge support', PARAMS.MESH_NAME), ...
                 'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.02 0.02 0.96 0.94]);
    tl = tiledlayout(fig, nRows, nCols, 'Padding', 'compact', 'TileSpacing', 'compact');
    title(tl, sprintf('%s — all %d views — free boundary edge support', char(PARAMS.MESH_NAME), numViews), ...
        'Interpreter', 'none', 'FontSize', 14);

    legHandles = [];
    legLabels = {};
    for v = 0:(numViews - 1)
        fprintf('  view %d/%d...\n', v, numViews - 1);
        ax = nexttile(tl);
        [hEdges, hSupported, hUnsupported] = render_view(v, projMatrixByView, sampledPts, labels, freePts, freeTangents, PARAMS, ax);
        if isempty(legHandles)
            [legHandles, legLabels] = collect_legend_handles(hEdges, hSupported, hUnsupported);
        end
    end

    if ~isempty(legHandles)
        lg = legend(legHandles, legLabels, 'Orientation', 'horizontal');
        lg.Layout.Tile = 'south';
    end

    if ~exist(fullfile(pwd, 'tmp'), 'dir')
        mkdir(fullfile(pwd, 'tmp'));
    end
    if PARAMS.SAVE_FIGURE == 1
        safeName = matlab.lang.makeValidName(char(PARAMS.MESH_NAME));
        savePath = fullfile(pwd, 'tmp', sprintf('%s_allviews_free_boundary_edge_support.png', safeName));
        try
            saveas(fig, savePath);
            fprintf('Saved combined figure to %s\n', savePath);
        catch ME
            fprintf('Warning: failed to save combined figure: %s\n', ME.message);
        end
    end
    fprintf('\nDone. Per-view data saved to %s\n', fullfile(pwd, 'tmp'));
else
    viewChoice = round(str2double(viewInput));
    if isnan(viewChoice)
        error('Invalid input: "%s". Enter a view index (0-%d) or "all".', viewInput, numViews - 1);
    end
    if viewChoice < 0 || viewChoice > numViews - 1
        error('View %d is out of range (found %d views; valid indices are 0-%d, or "all").', ...
            viewChoice, numViews, numViews - 1);
    end
    render_view(viewChoice, projMatrixByView, sampledPts, labels, freePts, freeTangents, PARAMS, []);
end

function [legHandles, legLabels] = collect_legend_handles(hEdges, hSupported, hUnsupported)
legHandles = [];
legLabels = {};
if ~isempty(hEdges)
    legHandles(end + 1) = hEdges;
    legLabels{end + 1} = '2D detected edges';
end
if ~isempty(hSupported)
    legHandles(end + 1) = hSupported;
    legLabels{end + 1} = 'Free boundary: supported';
end
if ~isempty(hUnsupported)
    legHandles(end + 1) = hUnsupported;
    legLabels{end + 1} = 'Free boundary: NOT supported';
end
end

function [hEdges, hSupported, hUnsupported] = render_view(viewIdx0, projMatrixByView, sampledPts, labels, freePts, freeTangents, PARAMS, ax)
% Projects free-boundary points to one camera view, checks edge support,
% and displays the result.
% If ax is empty, a standalone figure is created (with legend, and saved
% to tmp/ as its own PNG per PARAMS.SAVE_FIGURE). If ax is a provided
% axes handle (e.g. a tile in a combined figure), the view is drawn
% compactly into it instead, with no per-view legend/figure save.
standalone = isempty(ax);
viewIdx1 = viewIdx0 + 1; % 1-based, indexes projMatrixByView
tauOrientationRad = deg2rad(PARAMS.TAU_ORIENTATION_DEG);

if viewIdx1 < 1 || viewIdx1 > numel(projMatrixByView)
    error('View %d is out of range (found %d views).', viewIdx0, numel(projMatrixByView));
end

projMatrix = projMatrixByView{viewIdx1};
if isstruct(projMatrix)
    f = fieldnames(projMatrix);
    if ~isempty(f)
        projMatrix = projMatrix.(f{1});
    end
end

% ---- detected 2D third-order edges for this view ----
edgesDir = fullfile(pwd, 'data', PARAMS.DATASET_NAME, PARAMS.SCENE_NAME, 'edges');
edgeFile = fullfile(edgesDir, sprintf('edges_%02d.mat', viewIdx0));
edges = zeros(0, 3); % [x, y, orientation]
if exist(edgeFile, 'file')
    edgeData = load(edgeFile);
    if isfield(edgeData, 'TO_edges')
        edges = edgeData.TO_edges;
    end
else
    fprintf('Warning: no edge file for view %d (%s)\n', viewIdx0, edgeFile);
end

% ---- project free-boundary points + tangents to this view ----
uv = project_points_to_image(freePts, projMatrix);
tangent2D = compute_camera_tangents(freePts, freeTangents, projMatrix);
theta = atan2(tangent2D(:, 2), tangent2D(:, 1));

keep = true(size(uv, 1), 1);
if PARAMS.DRAW_ONLY_IN_IMAGE_BOUNDS == 1
    keep = keep & uv(:, 1) >= 1 & uv(:, 1) <= PARAMS.PLANE_COLS & ...
                   uv(:, 2) >= 1 & uv(:, 2) <= PARAMS.PLANE_ROWS;
end
keep = keep & all(isfinite(tangent2D), 2); % drop points behind the camera / degenerate tangent

uv = uv(keep, :);
theta = theta(keep);
fprintf('  %d free-boundary points selected for edge-support evaluation (view %d)\n', size(uv, 1), viewIdx0);

% ---- build the uniform spatial grid over the 2D edges (once) ----
edgeGrid = build_edge_grid(edges, PARAMS.GRID_CELL_SIZE, PARAMS.PLANE_ROWS, PARAMS.PLANE_COLS);

% ---- coarse-to-fine support check: grid lookup + local distance/orientation test ----
nPts = size(uv, 1);
supported = false(nPts, 1);
candidatesExamined = zeros(nPts, 1);
for i = 1:nPts
    [row, col] = point_to_cell(uv(i, 1), uv(i, 2), PARAMS.GRID_CELL_SIZE, edgeGrid.numRows, edgeGrid.numCols);
    candidateIdx = gather_candidate_edges(edgeGrid, row, col);
    candidatesExamined(i) = numel(candidateIdx);
    supported(i) = check_edge_support(uv(i, :), theta(i), edges, candidateIdx, PARAMS.TAU_DISTANCE, tauOrientationRad);
end

nSupported = sum(supported);
avgCandidates = 0;
if nPts > 0
    avgCandidates = mean(candidatesExamined);
end
fprintf('  %d/%d free-boundary points supported (%.1f%%)\n', nSupported, nPts, 100 * nSupported / max(1, nPts));
fprintf('  grid: %dx%d cells of %d px, avg %.1f candidate edges examined per point (vs %d edges brute-force)\n', ...
        edgeGrid.numRows, edgeGrid.numCols, PARAMS.GRID_CELL_SIZE, avgCandidates, size(edges, 1));

% ---- display ----
if standalone
    fig = figure('Name', sprintf('%s - view %d - free boundary edge support', PARAMS.MESH_NAME, viewIdx0), ...
                 'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.15 0.1 0.7 0.8]);
    ax = axes(fig);
end
hold(ax, 'on');

if PARAMS.SHOW_GRID == 1
    draw_grid_lines(ax, PARAMS.GRID_CELL_SIZE, PARAMS.PLANE_ROWS, PARAMS.PLANE_COLS);
end

hEdges = [];
if ~isempty(edges)
    hEdges = scatter(ax, edges(:, 1), edges(:, 2), 3, [0 0.6 0], 'filled', 'DisplayName', '2D detected edges');
end

hSupported = [];
if any(supported)
    hSupported = scatter(ax, uv(supported, 1), uv(supported, 2), 10, [0 0.45 0.9], 'filled', 'DisplayName', 'Free boundary: supported');
end

hUnsupported = [];
if any(~supported)
    hUnsupported = scatter(ax, uv(~supported, 1), uv(~supported, 2), 10, [1 0 0], 'filled', 'DisplayName', 'Free boundary: NOT supported');
end

axis(ax, 'equal');
xlim(ax, [1, PARAMS.PLANE_COLS]);
ylim(ax, [1, PARAMS.PLANE_ROWS]);
set(ax, 'YDir', 'reverse', 'XTick', [], 'YTick', []);

if standalone
    title(ax, sprintf('%s — view %d — %d/%d free boundary pts supported (%.0f%%)', ...
          char(PARAMS.MESH_NAME), viewIdx0, nSupported, nPts, 100 * nSupported / max(1, nPts)), ...
          'Interpreter', 'none', 'FontSize', 11);
    legendHandles = [hEdges, hSupported, hUnsupported];
    if ~isempty(legendHandles)
        legend(ax, legendHandles, 'Location', 'southoutside', 'Orientation', 'horizontal');
    end
else
    title(ax, sprintf('view %d — %.0f%% supported', viewIdx0, 100 * nSupported / max(1, nPts)), ...
          'FontSize', 8);
end
hold(ax, 'off');

if ~exist(fullfile(pwd, 'tmp'), 'dir')
    mkdir(fullfile(pwd, 'tmp'));
end
safeName = matlab.lang.makeValidName(char(PARAMS.MESH_NAME));

if standalone && PARAMS.SAVE_FIGURE == 1
    savePath = fullfile(pwd, 'tmp', sprintf('%s_view%02d_free_boundary_edge_support.png', safeName, viewIdx0));
    try
        saveas(fig, savePath);
        fprintf('Saved figure to %s\n', savePath);
    catch ME
        fprintf('Warning: failed to save figure: %s\n', ME.message);
    end
end

if PARAMS.SAVE_SAMPLES == 1
    savePath = fullfile(pwd, 'tmp', sprintf('%s_view%02d_free_boundary_edge_support.mat', safeName, viewIdx0));
    save(savePath, 'sampledPts', 'labels', 'freePts', 'uv', 'theta', 'supported', 'viewIdx0', '-v7.3');
    fprintf('Saved sample/support data to %s\n', savePath);
end
end

function uv = project_points_to_image(points3d, projMatrix)
homPts = [points3d, ones(size(points3d, 1), 1)]';
pix = projMatrix * homPts;
valid = abs(pix(3, :)) > 1e-12;
pix = pix(:, valid);
if ~any(valid)
    uv = zeros(0, 2);
    return;
end

uv = pix(1:2, :) ./ pix(3, :);
% Match codebase pixel convention where integer pixel centers are addressed as +1.
uv = uv' + 1;
end

function projMatrixByView = load_projection_matrices(projDir)
projMatrixByView = {};
if ~exist(projDir, 'dir')
    return;
end

files = dir(fullfile(projDir, '*.projmatrix'));
if isempty(files)
    return;
end

names = {files.name};
order = zeros(numel(names), 1);
for i = 1:numel(names)
    tok = regexp(names{i}, '^(\d+)\.projmatrix$', 'tokens', 'once');
    if isempty(tok)
        order(i) = Inf;
    else
        order(i) = str2double(tok{1});
    end
end
[~, idx] = sort(order);
files = files(idx);

for i = 1:numel(files)
    projMatrixByView{end + 1} = load(fullfile(files(i).folder, files(i).name)); %#ok<AGROW>
end
end

function edgeGrid = build_edge_grid(edges, cellSize, imgRows, imgCols)
%BUILD_EDGE_GRID Bucket 2D edges once into a uniform pixel grid.
% edgeGrid.cells{row, col} holds the row indices into `edges` that fall
% inside that grid cell. Built once per view and reused for every query
% point so the per-point cost stays O(edges-per-cell), not O(N).
numRows = max(1, ceil(imgRows / cellSize));
numCols = max(1, ceil(imgCols / cellSize));
cells = cell(numRows, numCols);

for i = 1:size(edges, 1)
    [r, c] = point_to_cell(edges(i, 1), edges(i, 2), cellSize, numRows, numCols);
    cells{r, c}(end + 1) = i; %#ok<AGROW>
end

edgeGrid.cellSize = cellSize;
edgeGrid.numRows = numRows;
edgeGrid.numCols = numCols;
edgeGrid.cells = cells;
end

function [row, col] = point_to_cell(x, y, cellSize, numRows, numCols)
row = floor((y - 1) / cellSize) + 1;
col = floor((x - 1) / cellSize) + 1;
row = min(max(row, 1), numRows);
col = min(max(col, 1), numCols);
end

function candidateIdx = gather_candidate_edges(edgeGrid, row, col)
% Collect edges from the query cell and its 8 neighbors. Since
% TAU_DISTANCE is much smaller than the grid cell size, any edge within
% matching distance of a point anywhere in the cell is guaranteed to lie
% in this 3x3 neighborhood.
rLo = max(1, row - 1);
rHi = min(edgeGrid.numRows, row + 1);
cLo = max(1, col - 1);
cHi = min(edgeGrid.numCols, col + 1);

candidateIdx = [];
for r = rLo:rHi
    for c = cLo:cHi
        candidateIdx = [candidateIdx, edgeGrid.cells{r, c}]; %#ok<AGROW>
    end
end
end

function supported = check_edge_support(uv, theta, edges, candidateIdx, tauDistance, tauOrientationRad)
supported = false;
if isempty(candidateIdx)
    return;
end

cand = edges(candidateIdx, :);
d = sqrt((cand(:, 1) - uv(1)).^2 + (cand(:, 2) - uv(2)).^2);
nearby = d <= tauDistance;
if ~any(nearby)
    return;
end

oriDiff = angular_diff_mod_pi(theta, cand(nearby, 3));
supported = any(oriDiff <= tauOrientationRad);
end

function d = angular_diff_mod_pi(a, b)
% Orientation is a line direction (period pi, not 2*pi), so wrap the
% difference into (-pi, pi] and then fold it into [0, pi/2].
raw = mod(a - b + pi, 2 * pi) - pi;
d = abs(raw);
d = min(d, pi - d);
end

function draw_grid_lines(ax, cellSize, imgRows, imgCols)
xLines = 1:cellSize:imgCols;
yLines = 1:cellSize:imgRows;

xData = [];
yData = [];
for x = xLines
    xData = [xData, x, x, NaN]; %#ok<AGROW>
    yData = [yData, 1, imgRows, NaN]; %#ok<AGROW>
end
for y = yLines
    xData = [xData, 1, imgCols, NaN]; %#ok<AGROW>
    yData = [yData, y, y, NaN]; %#ok<AGROW>
end

plot(ax, xData, yData, 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5, 'HandleVisibility', 'off');
end

function [sampledPts, boundaryVertexIds, boundaryLabels] = sample_mesh_boundary_points(pts, tri, targetSampleCount, curve1, curve2, tol)
% Extract boundary edges (edges used by exactly one triangle)
allEdges = [tri(:, [1 2]); tri(:, [2 3]); tri(:, [3 1])];
sortedEdges = sort(allEdges, 2);
[uniqEdges, ~, edgeMap] = unique(sortedEdges, 'rows');
edgeUseCount = accumarray(edgeMap, 1);
boundaryEdges = uniqEdges(edgeUseCount == 1, :);

boundaryLabels = strings(0, 1);
if isempty(boundaryEdges)
    sampledPts = zeros(0, 3);
    boundaryVertexIds = zeros(0, 1);
    return;
end

boundaryVertexIds = unique(boundaryEdges(:));

if nargin < 3 || isempty(targetSampleCount)
    targetSampleCount = size(boundaryEdges, 1);
end
targetSampleCount = max(1, round(double(targetSampleCount)));

% Build an ordered boundary contour so that neighboring samples are adjacent.
maxVid = max(boundaryVertexIds);
neighbors = cell(maxVid, 1);
for k = 1:size(boundaryEdges, 1)
    v1 = boundaryEdges(k, 1);
    v2 = boundaryEdges(k, 2);
    neighbors{v1}(end+1) = v2;
    neighbors{v2}(end+1) = v1;
end

visited = false(maxVid, 1);
orderedLoops = {};
for k = 1:numel(boundaryVertexIds)
    vid = boundaryVertexIds(k);
    if visited(vid)
        continue;
    end

    loopVerts = vid;
    curr = vid;
    prev = 0;
    while true
        nbrs = neighbors{curr};
        nextCandidates = nbrs(nbrs ~= prev);
        if isempty(nextCandidates)
            break;
        end
        nextV = nextCandidates(1);
        if nextV == vid
            break;
        end
        loopVerts(end+1) = nextV; %#ok<AGROW>
        prev = curr;
        curr = nextV;
    end

    orderedLoops{end+1} = loopVerts; %#ok<AGROW>
    visited(loopVerts) = true;
end

if isempty(orderedLoops)
    sampledPts = zeros(0, 3);
    boundaryLabels = strings(0, 1);
    return;
end

allEdgeVerts1 = [];
allEdgeVerts2 = [];
for li = 1:numel(orderedLoops)
    loopVerts = orderedLoops{li};
    if numel(loopVerts) < 2
        continue;
    end
    isClosed = any(neighbors{loopVerts(end)} == loopVerts(1));
    allEdgeVerts1 = [allEdgeVerts1; loopVerts(:)]; %#ok<AGROW>
    if isClosed
        allEdgeVerts2 = [allEdgeVerts2; loopVerts(2:end).'; loopVerts(1)]; %#ok<AGROW>
    else
        allEdgeVerts2 = [allEdgeVerts2; loopVerts(2:end).']; %#ok<AGROW>
    end
end

if isempty(allEdgeVerts1)
    sampledPts = zeros(0, 3);
    boundaryLabels = strings(0, 1);
    return;
end

p1 = pts(allEdgeVerts1, :);
p2 = pts(allEdgeVerts2, :);
edgeLen = sqrt(sum((p2 - p1).^2, 2));
valid = edgeLen > 1e-12;
if ~any(valid)
    sampledPts = pts(boundaryVertexIds, :);
    boundaryLabels = classify_boundary_samples(sampledPts, curve1, curve2, tol);
    return;
end

p1 = p1(valid, :);
p2 = p2(valid, :);
edgeLen = edgeLen(valid);

cumLen = cumsum(edgeLen);
totalLen = cumLen(end);
q = ((1:targetSampleCount)' - 0.5) / targetSampleCount * totalLen;
edgeIdx = arrayfun(@(x) find(cumLen >= x, 1, 'first'), q);
prevCum = [0; cumLen(1:end-1)];
t = (q - prevCum(edgeIdx)) ./ edgeLen(edgeIdx);
sampledPts = (1 - t) .* p1(edgeIdx, :) + t .* p2(edgeIdx, :);
boundaryLabels = classify_boundary_samples(sampledPts, curve1, curve2, tol);
% Smooth labels to remove isolated single-point flips
boundaryLabels = smooth_boundary_labels(boundaryLabels, 3);
end

function boundaryLabels = smooth_boundary_labels(boundaryLabels, windowSize)
% Smooth boundary labels to remove isolated single-point flips
% Uses majority voting within a window to reduce fragmentation
if nargin < 2 || isempty(windowSize)
    windowSize = 3;
end

n = numel(boundaryLabels);
if n < windowSize
    return;  % Too small to smooth
end

smoothedLabels = boundaryLabels;
halfWindow = floor(windowSize / 2);

for i = 1:n
    startIdx = max(1, i - halfWindow);
    endIdx = min(n, i + halfWindow);
    windowLabels = boundaryLabels(startIdx:endIdx);

    % Find the most common label in the window
    [labelCounts, uniqueLabels] = histcounts(categorical(windowLabels));
    [~, maxIdx] = max(labelCounts);
    smoothedLabels(i) = uniqueLabels(maxIdx);
end

boundaryLabels = smoothedLabels;
end

function boundaryLabels = classify_boundary_samples(sampledPts, curve1, curve2, tol)
if nargin < 4 || isempty(tol)
    tol = [];
end

boundaryLabels = strings(size(sampledPts, 1), 1);
boundaryLabels(:) = "free";
if isempty(sampledPts) || size(sampledPts, 2) ~= 3
    return;
end

if isempty(curve1) && isempty(curve2)
    return;
end

if isempty(curve1) || isempty(curve2)
    curveToUse = curve1;
    if isempty(curveToUse)
        curveToUse = curve2;
    end
    if isempty(curveToUse)
        return;
    end
    for i = 1:size(sampledPts, 1)
        d = min_distance_to_curve(sampledPts(i, :), curveToUse);
        if isempty(tol) || d <= tol
            boundaryLabels(i) = "curve1";
        end
    end
    return;
end

if isempty(tol)
    spacing1 = median(sqrt(sum(diff(curve1, 1, 1).^2, 2)));
    spacing2 = median(sqrt(sum(diff(curve2, 1, 1).^2, 2)));
    tol = max(1e-6, 0.5 * max(spacing1, spacing2));
end

for i = 1:size(sampledPts, 1)
    d1 = min_distance_to_curve(sampledPts(i, :), curve1);
    d2 = min_distance_to_curve(sampledPts(i, :), curve2);
    if d1 <= tol && d1 <= d2
        boundaryLabels(i) = "curve1";
    elseif d2 <= tol && d2 < d1
        boundaryLabels(i) = "curve2";
    else
        boundaryLabels(i) = "free";
    end
end
end

function d = min_distance_to_curve(pt, curve)
if isempty(curve) || size(curve, 1) == 0
    d = Inf;
    return;
end

d = min(sqrt(sum((curve - pt).^2, 2)));
end

function curveIds = parse_surface_curve_ids(surfaceName)
curveIds = [];
nameChars = char(surfaceName);
match = regexp(nameChars, '^loftsurf_(\d+)_(\d+)', 'tokens', 'once');
if ~isempty(match)
    curveIds = [str2double(match{1}), str2double(match{2})];
end
end
