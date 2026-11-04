function [gridId, col, row, grid] = arbitarary_edge_to_Grid_assocication(pts, cellSize, imageSize)
%ARBITARARY_EDGE_TO_GRID_ASSOCICATION Hash-table style lookup: 2D edge point -> grid cell.
% The grid is the same one drawn in Occlusion_2D.m: lines every cellSize
% pixels starting at 0, over an imageSize x imageSize frame, in the same
% 0-based pixel coordinates as the edge points.
%
%   col = (x - mod(x, cell)) / cell   (horizontal index, 0-based)
%   row = (y - mod(y, cell)) / cell   (vertical index, 0-based)
%   id  = row * numCols + col + 1     (1-based, row-major)
%
% Usage:
%   [gridId, col, row, grid] = arbitarary_edge_to_Grid_assocication(pts, 30, 800)
%       pts is N x 2 [x y]; points outside the image give NaN.
%   arbitarary_edge_to_Grid_assocication()   % no args: run a printed/plotted demo
if nargin == 0
    run_demo();
    return;
end
if nargin < 2 || isempty(cellSize)
    cellSize = 30;
end
if nargin < 3 || isempty(imageSize)
    imageSize = 800;
end

grid = make_grid(cellSize, imageSize);
[gridId, col, row] = edge_to_grid_id(pts, grid);
end

function run_demo()
close all;
PARAMS.GRID_CELL_SIZE = 30;   % pixels
PARAMS.IMAGE_SIZE = 800;      % pixels (square image)

% ---- edge points to look up: one [x, y] per row ----
queryPts = [ ...
    226.75, 552.50;
    593.99, 543.99;
    0,      0;
    799,    799;
    30,     60;     % exactly on a grid line -> belongs to the cell to its right/below
];

[gridId, col, row, grid] = arbitarary_edge_to_Grid_assocication(queryPts, PARAMS.GRID_CELL_SIZE, PARAMS.IMAGE_SIZE);
fprintf('Grid: %d cols x %d rows of %d px cells (%d cells total)\n', ...
        grid.numCols, grid.numRows, grid.cellSize, grid.numCols * grid.numRows);


fprintf('\n      x        y    | col row |  grid id\n');
for i = 1:size(queryPts, 1)
    if isnan(gridId(i))
        fprintf('%8.2f %8.2f  |   -   - |  outside image\n', queryPts(i, 1), queryPts(i, 2));
    else
        fprintf('%8.2f %8.2f  | %3d %3d | %5d\n', queryPts(i, 1), queryPts(i, 2), col(i), row(i), gridId(i));
    end
end

% ---- visualize the grid and the queried points / their cells ----
fig = figure('Name', 'Edge point -> grid cell', 'NumberTitle', 'off');
ax = axes(fig);
hold(ax, 'on');

for i = 1:size(queryPts, 1)
    if isnan(gridId(i))
        continue;
    end
    x0 = col(i) * grid.cellSize;
    y0 = row(i) * grid.cellSize;
    rectangle(ax, 'Position', [x0, y0, grid.cellSize, grid.cellSize], ...
              'FaceColor', [1 0.9 0.6], 'EdgeColor', 'none');
end

lines = 0:grid.cellSize:grid.imageSize - 1;
nG = numel(lines);
plot(ax, [lines; lines], repmat([0; grid.imageSize - 1], 1, nG), '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5);
plot(ax, repmat([0; grid.imageSize - 1], 1, nG), [lines; lines], '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5);

scatter(ax, queryPts(:, 1), queryPts(:, 2), 30, [1 0 0], 'filled');
for i = 1:size(queryPts, 1)
    if ~isnan(gridId(i))
        text(ax, queryPts(i, 1) + 4, queryPts(i, 2) - 6, sprintf('id %d', gridId(i)), 'FontSize', 8);
    end
end

axis(ax, 'equal');
xlim(ax, [0 grid.imageSize - 1]);
ylim(ax, [0 grid.imageSize - 1]);
set(ax, 'YDir', 'reverse');
title(ax, sprintf('2D edge points -> %dx%d px grid cells', grid.cellSize, grid.cellSize));
hold(ax, 'off');
end

function grid = make_grid(cellSize, imageSize)
grid.cellSize = cellSize;
grid.imageSize = imageSize;
grid.numCols = ceil(imageSize / cellSize);
grid.numRows = ceil(imageSize / cellSize);
end

function [gridId, col, row] = edge_to_grid_id(pts, grid)
%EDGE_TO_GRID_ID Map 2D points (N x 2, [x y]) to grid cell indices.
% Points outside the image get NaN.
x = pts(:, 1);
y = pts(:, 2);
col = (x - mod(x, grid.cellSize)) / grid.cellSize;   % horizontal cell index (0-based)
row = (y - mod(y, grid.cellSize)) / grid.cellSize;   % vertical cell index (0-based)

gridId = row * grid.numCols + col + 1;
outside = x < 0 | y < 0 | x >= grid.imageSize | y >= grid.imageSize | ~isfinite(x) | ~isfinite(y);
gridId(outside) = NaN;
col(outside) = NaN;
row(outside) = NaN;
end
