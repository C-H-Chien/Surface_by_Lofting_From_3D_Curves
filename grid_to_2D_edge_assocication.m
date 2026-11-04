function [hasEdge, edgePts, edgeCount, grid, edgeIdx, litPts] = grid_to_2D_edge_assocication(gridIds, edges, cellSize, imageSize, viewId, doPlot)
%GRID_TO_2D_EDGE_ASSOCICATION Reverse of arbitarary_edge_to_Grid_assocication.
% Given grid cell ids, return the 2D edge points that lie inside those cells.
% Uses the same grid (cellSize px cells from 0 over an imageSize x imageSize
% frame, row-major 1-based ids) and the same edge -> cell mapping, so the
% two files always agree.
%
%   id = row * numCols + col + 1
%
% CALLED FROM ANOTHER FILE:
%   [hasEdge, edgePts, edgeCount, grid, edgeIdx, litPts] = ...
%       grid_to_2D_edge_assocication(gridIds, edges, cellSize, imageSize, viewId, doPlot)
%
%   Inputs (all but gridIds optional; [] = default):
%     gridIds   : K x 1 list of grid ids (1-based). Invalid ids give false / 0.
%     edges     : N x >=2 edge points [x y theta ...]. If omitted/empty, the
%                 clean GT-associated edges of `viewId` are loaded from
%                 tools/GT_edge_corresp_ABC_NEF/GT_3D_2D_assoc_0325.json.
%     cellSize  : pixels per cell (default 30)
%     imageSize : square image size in pixels (default 800)
%     viewId    : 0-based view for the GT edges when `edges` is omitted (default 3)
%     doPlot    : true to also draw the grid / lit cells (default false)
%
%   Outputs:
%     hasEdge   : K x 1 logical, true if the cell contains >= 1 edge point.
%     edgePts   : K x 1 cell; edgePts{k} = edge points inside cell gridIds(k).
%     edgeCount : K x 1 number of edge points in that cell.
%     grid      : struct (cellSize, imageSize, numCols, numRows,
%                 cellEdgeCount = numRows x numCols counts for the whole grid).
%     edgeIdx   : K x 1 cell, row indices into `edges` of those points.
%     litPts    : all edge points inside the requested cells, stacked (M x ...).
%
% NOT CALLED (no arguments): runs the demo -- edit queryIds in run_demo()
% below, run this file, and it prints and plots those cells.
if nargin == 0
    run_demo();
    return;
end
if nargin < 2
    edges = [];
end
if nargin < 3 || isempty(cellSize)
    cellSize = 30;
end
if nargin < 4 || isempty(imageSize)
    imageSize = 800;
end
if nargin < 5 || isempty(viewId)
    viewId = 3;
end
if nargin < 6 || isempty(doPlot)
    doPlot = false;
end

if isempty(edges)
    edges = load_gt_view_edges(default_corresp_json(), viewId);
end

% ---- build the hash table: grid id -> edge point indices (once) ----
[edgeGridId, ~, ~, grid] = arbitarary_edge_to_Grid_assocication(edges(:, 1:2), cellSize, imageSize);
numCells = grid.numCols * grid.numRows;

inside = ~isnan(edgeGridId);
edgeRows = find(inside);
cellOf = edgeGridId(inside);
cellEdges = accumarray(cellOf, edgeRows, [numCells, 1], @(v) {v}, {zeros(0, 1)});
cellCount = cellfun(@numel, cellEdges);

grid.cellEdgeCount = reshape(cellCount, grid.numCols, grid.numRows)';  % (row, col)

% ---- look up the requested cells ----
gridIds = gridIds(:);
K = numel(gridIds);
valid = gridIds >= 1 & gridIds <= numCells & gridIds == round(gridIds);
hasEdge = false(K, 1);
edgeCount = zeros(K, 1);
edgeIdx = repmat({zeros(0, 1)}, K, 1);
edgePts = repmat({zeros(0, size(edges, 2))}, K, 1);
hasEdge(valid) = cellCount(gridIds(valid)) > 0;
edgeCount(valid) = cellCount(gridIds(valid));
edgeIdx(valid) = cellEdges(gridIds(valid));
for k = find(valid)'
    edgePts{k} = edges(edgeIdx{k}, :);
end
litPts = vertcat(edgePts{:});
if isempty(litPts)
    litPts = zeros(0, size(edges, 2));
end

if doPlot
    plot_cells(gridIds, hasEdge, edgePts, edges, grid, viewId);
end
end

function run_demo()
close all;

% =====================================================================
% USER SETTINGS -- edit these, then run the file with no arguments
% =====================================================================
queryIds = [389 289 281 1];   % grid ids to check (1-based, row-major)
VIEW_ID = 3;                  % 0-based view whose GT 2D edges are used
GRID_CELL_SIZE = 30;          % keep in sync with Occlusion_2D.m
IMAGE_SIZE = 800;
% =====================================================================

edges = load_gt_view_edges(default_corresp_json(), VIEW_ID);

[hasEdge, edgePts, edgeCount, g] = grid_to_2D_edge_assocication( ...
    queryIds, edges, GRID_CELL_SIZE, IMAGE_SIZE, VIEW_ID, true);

fprintf('View %d: %d GT-associated edge points, %d/%d cells contain edges\n', VIEW_ID, size(edges, 1), ...
        nnz(g.cellEdgeCount > 0), g.numCols * g.numRows);
fprintf('\n grid id | col row | has edge | #edge pts\n');
for i = 1:numel(queryIds)
    c = mod(queryIds(i) - 1, g.numCols);
    r = floor((queryIds(i) - 1) / g.numCols);
    fprintf('%8d | %3d %3d | %8s | %5d\n', queryIds(i), c, r, string(hasEdge(i)), edgeCount(i));
end

% ---- the actual 2D edge points inside each queried cell ----
for i = 1:numel(queryIds)
    fprintf('\nGrid id %d: %d edge point(s)\n', queryIds(i), edgeCount(i));
    P = edgePts{i};
    for j = 1:size(P, 1)
        fprintf('    (x = %8.3f, y = %8.3f, theta = %7.4f)\n', P(j, 1), P(j, 2), P(j, 3));
    end
end
end

function plot_cells(gridIds, hasEdge, edgePts, edges, g, viewId)
% specified cells outlined; light green fill if the cell has 2D edges
fig = figure('Name', 'Grid cell -> 2D edges', 'NumberTitle', 'off');
ax = axes(fig);
hold(ax, 'on');
cw = g.cellSize;

hitIds = gridIds(hasEdge);
x0 = mod(hitIds(:) - 1, g.numCols) * cw;
y0 = floor((hitIds(:) - 1) / g.numCols) * cw;
if ~isempty(hitIds)
    patch(ax, [x0, x0 + cw, x0 + cw, x0]', [y0, y0, y0 + cw, y0 + cw]', [0.75 0.92 0.75], ...
          'EdgeColor', 'none', 'HandleVisibility', 'off');
end

lines = 0:cw:g.imageSize - 1;
nG = numel(lines);
plot(ax, [lines; lines], repmat([0; g.imageSize - 1], 1, nG), '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5, 'HandleVisibility', 'off');
plot(ax, repmat([0; g.imageSize - 1], 1, nG), [lines; lines], '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5, 'HandleVisibility', 'off');

scatter(ax, edges(:, 1), edges(:, 2), 4, [0.3 0.3 0.3], 'filled', 'HandleVisibility', 'off');
% points returned by the hash table for the queried cells, emphasized
for i = 1:numel(gridIds)
    if hasEdge(i)
        scatter(ax, edgePts{i}(:, 1), edgePts{i}(:, 2), 25, [0 0.3 1], 'filled', 'HandleVisibility', 'off');
    end
end

for i = 1:numel(gridIds)
    if isnan(gridIds(i)) || gridIds(i) < 1 || gridIds(i) > g.numCols * g.numRows
        continue;
    end
    c = mod(gridIds(i) - 1, g.numCols);
    r = floor((gridIds(i) - 1) / g.numCols);
    if hasEdge(i)
        col = [0 0.5 0];
    else
        col = [0.85 0 0];
    end
    rectangle(ax, 'Position', [c * cw, r * cw, cw, cw], 'EdgeColor', col, 'LineWidth', 2);
    text(ax, c * cw + 2, r * cw + 8, sprintf('%d', gridIds(i)), 'FontSize', 8, 'Color', col);
end

axis(ax, 'equal');
xlim(ax, [0 g.imageSize - 1]);
ylim(ax, [0 g.imageSize - 1]);
set(ax, 'YDir', 'reverse');
title(ax, sprintf('View %d (GT edges): queried cells outlined; light green = cell has 2D edges, red = empty', viewId), ...
      'FontSize', 10);
hold(ax, 'off');
end

function p = default_corresp_json()
p = fullfile(pwd, 'tools', 'GT_edge_corresp_ABC_NEF', 'GT_3D_2D_assoc_0325.json');
end

function edges = load_gt_view_edges(jsonPath, viewId)
%LOAD_GT_VIEW_EDGES Unique GT-associated 2D edge points (x, y, theta) of one view.
corr = jsondecode(fileread(jsonPath));
if viewId < 0 || viewId >= corr.n_views
    error('VIEW_ID %d out of range (0..%d).', viewId, corr.n_views - 1);
end
assocViews = arrayfun(@(a) a.view, corr.associations);
blk = corr.associations(assocViews == viewId);
if isempty(blk.edgel_index)
    edges = zeros(0, 3);
    return;
end
edges = reshape(blk.edge_points, [], 3);
[~, firstIdx] = unique(blk.edgel_index(:));   % several 3D samples can share one edgel
edges = edges(sort(firstIdx), :);
end
