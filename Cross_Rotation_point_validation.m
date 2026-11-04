close all;

addpath(fullfile(pwd, 'util'));
addpath(fullfile(pwd, 'util', 'plyread'));

% Standalone script: same outputs as Occlusion_2D.m, minus the grid
% 1) runs on EVERY .ply surface in tmp/filtered_surfaces
% 2) Figure 1: GT .obj, lofted surface .ply and the two curves of the pair (3D)
% 3) Figure 2: camera view -- GT 2D edge points of curve 1 / curve 2 in VIEW_ID
% 4) Figure 3: linear interpolation between those two 2D curves in VIEW_ID
% No grid lines, no grid-cell highlighting, no gray GT 2D edge overlay.
% Figures are only drawn when PARAMS.SHOW_FIGURES == 1; the per-surface
% classification results are collected in the `results` table either way.

% ---- what to run ----
PARAMS.PLY_DIR  = fullfile(pwd, 'tmp', 'filtered_surfaces');
PARAMS.PLY_NAME = '';   % '' = run ALL .ply in PLY_DIR; otherwise only this one, e.g. 'loftsurf_8_17_reverse.ply'
                        % (.ply extension optional; a cell array of names or a wildcard such as 'loftsurf_8_17_*' also works)
PARAMS.GT_FILE  = fullfile(pwd, 'data', 'ABC-NEF', '00000325', ...
    '00000325_3062bccff48e47a2b9de05e3_trimesh_020.obj');
PARAMS.VIEW_ID  = 'all';   % 0-based view id for the 2D edge visualization: a single id, a vector (e.g. [3 10 20]),
                           % or 'all' for every view (0..n_views-1, 0-49 here)
PARAMS.CORRESP_JSON = fullfile(pwd, 'tools', 'GT_edge_corresp_ABC_NEF', 'GT_3D_2D_assoc_0325.json');
PARAMS.GRID_CELL_SIZE = 5;  % pixels; only used to look up the lit points, the grid is not drawn (0 = no lit points)
PARAMS.INTERP_STEPS = 10;   % number of in-between curves between curve 1 and curve 2
PARAMS.SHOW_SURFACE = 1;   % 1 = also draw the lofted .ply surface
PARAMS.SHOW_FIGURES = 0;   % 1 = draw the figures (off for now: one set per surface)
PARAMS.RESULTS_FILE = fullfile(pwd, 'tmp', 'cross_rotation_results.mat');   % per-(view, surface) results, read by Occlusion_2D_filter.m ('' = do not save)
PARAMS.Linear_Interpolaiton_visualization = 0;   % 1 = extra figure like Linear_Interpolaiton_visualization.m (covered grid cells, grid, curves 1/2, other edges, GT 2D edge overlay)

% ---- curves (same source proximity_paring.m uses) ----
inputCurves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;

% ======================================================================
% GT 2D edge points of the camera view (shared by all surfaces)
% (lookup built by tools/GT_edge_corresp_construction.py)
% Pipeline curve k (1-based) <-> GT curve_id k-1 (0-based).
% ======================================================================
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
nView = numel(viewIds);
fprintf('Processing %d surfaces x %d views from %s\n', nSurf, nView, PARAMS.PLY_DIR);

% one row per (view, surface)
nRows = nSurf * nView;
resView = nan(nRows, 1);
resName = strings(nRows, 1);
resCurve1 = nan(nRows, 1);
resCurve2 = nan(nRows, 1);
resNotOnPair = nan(nRows, 1);    % lit points not on curve 1/2
resAutoOutside = nan(nRows, 1);  % excluded by the y-range check (orange)
resGreen = nan(nRows, 1);        % tested with d1..d4
resWithin = nan(nRows, 1);
resOutside = nan(nRows, 1);      % green points classified outside
resStatus = strings(nRows, 1);

for vi = 1:nView
PARAMS.VIEW_ID = viewIds(vi);   % the code below reads the current view from here
fprintf('\n########## VIEW %d ##########\n', PARAMS.VIEW_ID);

blk = corr.associations(assocViews == PARAMS.VIEW_ID);
if isempty(blk.point_index)
    ptIdx = zeros(0, 1);
    edgePts = zeros(0, 3);
else
    ptIdx = blk.point_index(:);               % 1-based GT 3D sample index
    edgePts = reshape(blk.edge_points, [], 3); % x, y, theta
end

% GT 2D edges of this view, one per unique detected edgel (used only to
% find the edges inside the covered cells; they are not drawn).
if isempty(blk.edgel_index)
    viewEdges = zeros(0, 3);
else
    viewEdges = reshape(blk.edge_points, [], 3);
    [~, ue] = unique(blk.edgel_index(:));
    viewEdges = viewEdges(sort(ue), :);
end

for s = 1:nSurf
    r = (vi - 1) * nSurf + s;   % row in the results table
    resView(r) = PARAMS.VIEW_ID;
    plyName = plyFiles(s).name;
    plyPath = fullfile(plyFiles(s).folder, plyName);
    resName(r) = plyName;
    fprintf('\n===== [%d/%d] %s =====\n', s, nSurf, plyName);

    % ---- curve pair ids from the .ply name ----
    tok = regexp(plyName, '^loftsurf_(\d+)_(\d+)', 'tokens', 'once');
    if isempty(tok)
        warning('Cannot parse curve pair ids from "%s" (expected loftsurf_<i>_<j>_*.ply); skipping.', plyName);
        resStatus(r) = "bad name";
        continue;
    end
    pairId = [str2double(tok{1}), str2double(tok{2})];
    resCurve1(r) = pairId(1);
    resCurve2(r) = pairId(2);
    fprintf('Surface %s -> curve pair (%d, %d)\n', plyName, pairId(1), pairId(2));

    if any(pairId < 1) || any(pairId > numel(inputCurves))
        warning('Pair (%d, %d) out of range (%d curves); skipping.', pairId(1), pairId(2), numel(inputCurves));
        resStatus(r) = "pair out of range";
        continue;
    end
    curve1 = inputCurves{pairId(1)};
    curve2 = inputCurves{pairId(2)};

    % GT 2D edge points of the camera view associated with curve 1 / curve 2
    curveSel = {pairId(1) - 1, pairId(2) - 1};
    edgeSets = cell(1, 2);
    for c = 1:2
        mask = gtCurveId(ptIdx) == curveSel{c};
        edgeSets{c} = edgePts(mask, :);
        fprintf('View %d, curve %d (GT id %d): %d 3D samples -> %d 2D edge points (of %d samples)\n', ...
                PARAMS.VIEW_ID, pairId(c), curveSel{c}, nnz(mask), size(edgeSets{c}, 1), nnz(gtCurveId == curveSel{c}));
    end

    e1 = edgeSets{1};
    e2 = edgeSets{2};

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
        resStatus(r) = "too few edge points";
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

        litOut = zeros(0, 3);
        litEdges = zeros(0, 3);

        % Cells covered by the interpolated region (sampled densely along each
        % rung), then the GT 2D edges inside those cells. The grid is only used
        % for the lookup -- nothing of it is drawn. Edges that are not on curve 1
        % or curve 2 are the red "lit" points of Occlusion_2D.m.
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
            if ~isempty(viewEdges)
                [~, ~, ~, ~, ~, litEdges] = grid_to_2D_edge_assocication( ...
                    coveredIds, viewEdges, PARAMS.GRID_CELL_SIZE, imgSize, PARAMS.VIEW_ID, false);
                onPair = ismember(litEdges(:, 1:2), [e1(:, 1:2); e2(:, 1:2)], 'rows');
                litOut = litEdges(~onPair, :);
                fprintf('Interpolated region covers %d grid cells; %d GT 2D edge points inside, %d not on curve 1/2\n', ...
                        numel(coveredIds), size(litEdges, 1), size(litOut, 1));
            end
        end

        % ---- grid view (same as Linear_Interpolaiton_visualization.m), toggle: Linear_Interpolaiton_visualization ----
        if PARAMS.Linear_Interpolaiton_visualization == 1 && PARAMS.GRID_CELL_SIZE > 0
            figG = figure('Name', sprintf('Grid view - view %d - curve pair (%d, %d)', PARAMS.VIEW_ID, pairId(1), pairId(2)), ...
                          'NumberTitle', 'off');
            axG = axes(figG);
            hold(axG, 'on');

            % grid cells covered by the interpolated region
            cw = gridInfo.cellSize;
            x0 = regionCol(firstIdx) * cw;
            y0 = regionRow(firstIdx) * cw;
            patch(axG, [x0, x0 + cw, x0 + cw, x0]', [y0, y0, y0 + cw, y0 + cw]', 'w', ...
                  'FaceColor', 'none', 'EdgeColor', [0 0.7 0], 'LineWidth', 1.5, 'HandleVisibility', 'off');

            % thin gray grid every GRID_CELL_SIZE pixels
            gridLines = 0:PARAMS.GRID_CELL_SIZE:imgSize - 1;
            nG = numel(gridLines);
            plot(axG, [gridLines; gridLines], repmat([0; imgSize - 1], 1, nG), '-', ...
                 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5, 'HandleVisibility', 'off');
            plot(axG, repmat([0; imgSize - 1], 1, nG), [gridLines; gridLines], '-', ...
                 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5, 'HandleVisibility', 'off');

            legendG = [];
            if ~isempty(viewEdges)
                hAllG = scatter(axG, viewEdges(:, 1), viewEdges(:, 2), 6, [0.35 0.35 0.35], 'filled', ...
                                'DisplayName', sprintf('GT 2D edges, view %d', PARAMS.VIEW_ID));
                legendG = hAllG;
            end
            if ~isempty(litOut)
                hLitG = scatter(axG, litOut(:, 1), litOut(:, 2), 24, [0.55 0 0.8], 'filled', ...
                                'MarkerEdgeColor', 'k', 'LineWidth', 0.5, ...
                                'DisplayName', sprintf('Other edge points: %d', size(litOut, 1)));
                legendG = [legendG, hLitG];
            end
            % curve 1 = blue, curve 2 = red, drawn on top
            hG1 = scatter(axG, A(:, 1), A(:, 2), 22, [0 0.3 1], 'filled', ...
                          'DisplayName', sprintf('Curve 1 (id %d) edge points', pairId(1)));
            hG2 = scatter(axG, B(:, 1), B(:, 2), 22, [1 0 0], 'filled', ...
                          'DisplayName', sprintf('Curve 2 (id %d) edge points', pairId(2)));
            legendG = [hG1, hG2, legendG];

            axis(axG, 'equal');
            xlim(axG, [0 imgSize - 1]);
            ylim(axG, [0 imgSize - 1]);
            set(axG, 'YDir', 'reverse');
            title(axG, sprintf('View %d: curve %d (blue) and curve %d (red)', ...
                  PARAMS.VIEW_ID, pairId(1), pairId(2)));
            legend(axG, legendG, 'Location', 'southoutside', 'Orientation', 'horizontal');
            hold(axG, 'off');
        end

        % correspondence rungs (every 5th sample) and in-between curve
        % parameters, used by the figures
        rung = 1:5:size(A, 1);
        tVals = linspace(0, 1, PARAMS.INTERP_STEPS + 2);

        % end-point vectors: curve 2 -> curve 1 at both ends of the interpolation
        % (the first and last rungs). Row 1 = start end, row 2 = finish end.
        endFrom = [B(1, :); B(end, :)];            % on curve 2
        endTo = [A(1, :); A(end, :)];              % on curve 1
        endVec = endTo - endFrom;                  % vector curve 2 -> curve 1
        fprintf('End vectors (curve 2 -> curve 1): start [%.2f %.2f] -> [%.2f %.2f], end [%.2f %.2f] -> [%.2f %.2f]\n', ...
                endFrom(1, :), endTo(1, :), endFrom(2, :), endTo(2, :));

        if PARAMS.SHOW_FIGURES == 1
            fig3 = figure('Name', sprintf('2D interpolation - view %d - curve pair (%d, %d)', PARAMS.VIEW_ID, pairId(1), pairId(2)), ...
                          'NumberTitle', 'off');
            ax3 = axes(fig3);
            hold(ax3, 'on');

            plot(ax3, [A(rung, 1), B(rung, 1)]', [A(rung, 2), B(rung, 2)]', '-', ...
                 'Color', [0.85 0.85 0.85], 'LineWidth', 0.5, 'HandleVisibility', 'off');

            % in-between curves, colored from red (curve 1) to blue (curve 2)
            for k = 2:numel(tVals) - 1
                t = tVals(k);
                P = (1 - t) * A + t * B;
                scatter(ax3, P(:, 1), P(:, 2), 8, (1 - t) * [1 0 0] + t * [0 0.3 1], 'filled', ...
                        'HandleVisibility', 'off');
            end

            h31 = scatter(ax3, A(:, 1), A(:, 2), 22, [1 0 0], 'filled', ...
                          'DisplayName', sprintf('Curve 1 (id %d) edge points', pairId(1)));
            h32 = scatter(ax3, B(:, 1), B(:, 2), 22, [0 0.3 1], 'filled', ...
                          'DisplayName', sprintf('Curve 2 (id %d) edge points', pairId(2)));
            hLit = scatter(ax3, litOut(:, 1), litOut(:, 2), 24, [0 0.7 0], 'filled', ...
                           'MarkerEdgeColor', 'k', 'LineWidth', 0.5, ...
                           'DisplayName', sprintf('Lit, not on curve 1/2: %d', size(litOut, 1)));
            hVec = quiver(ax3, endFrom(:, 1), endFrom(:, 2), endVec(:, 1), endVec(:, 2), 0, ...
                          'Color', [0.55 0 0.8], 'LineWidth', 2, 'MaxHeadSize', 0.5, ...
                          'DisplayName', 'End-point vectors (curve 2 -> curve 1)');

            axis(ax3, 'equal');
            xlim(ax3, [0 imgSize - 1]);
            ylim(ax3, [0 imgSize - 1]);
            set(ax3, 'YDir', 'reverse');
            set_pixel_axes(ax3, imgSize);
            title(ax3, sprintf('View %d: linear interpolation between curve %d and curve %d (%d steps)', ...
                  PARAMS.VIEW_ID, pairId(1), pairId(2), PARAMS.INTERP_STEPS));
            legend(ax3, [h31, h32, hLit, hVec], 'Location', 'southoutside', 'Orientation', 'horizontal');
            hold(ax3, 'off');
        end

        % longest of the two end vectors -> [a; b]
        [vLen, longIdx] = max(sqrt(sum(endVec.^2, 2)));
        vec = endVec(longIdx, :)';                 % [a; b]
        a = vec(1);
        b = vec(2);

        % rotation matrix from [a; b]. [a b; -b a] alone is a rotation scaled by
        % |v|, so divide by |v|. R * [a; b] = [|v|; 0] (rotates v onto the +x axis).
        Rot = [a b; -b a] / vLen;
        fprintf('Longest end vector: %s end, [a; b] = [%.4f; %.4f], |v| = %.4f\n', ...
                end_name(longIdx), a, b, vLen);
        fprintf('Rotation matrix = [a b; -b a] / |v|:\n');
        disp(Rot);
        fprintf('R*R'' = I check: %.2e, det(R) = %.4f, R*v = [%.4f; %.4f]\n', ...
                norm(Rot * Rot' - eye(2)), det(Rot), Rot * vec);

        % ==================================================================
        % Figure 4: same as Figure 3 after translating + rotating.
        % Translate so the curve 2 end point of the longest vector sits at the
        % origin, then rotate by Rot: that vector now lies along the +x axis.
        % ==================================================================
        origin = endFrom(longIdx, :);
        % All points of a set are rotated in ONE matrix product:
        %   [new x ... ]   = Rot * [old x ... ]   (2 x N)
        %   [new y ... ]           [old y ... ]
        xform = @(P) rotate_points(Rot, P, origin);
        Ar = xform(A);
        Br = xform(B);
        endFromR = xform(endFrom);
        endToR = xform(endTo);
        endVecR = endToR - endFromR;
        litOutR = zeros(0, 2);
        if ~isempty(litOut)
            litOutR = xform(litOut(:, 1:2));
        end

        % Non c1/c2 points at or above the top of EITHER curve, or at or below the
        % bottom of EITHER curve, are automatically "outside region" (orange). So
        % every remaining point has a c1 point and a c2 point strictly above and
        % strictly below it. For those, a thin light-blue dotted horizontal line
        % is drawn at their y.
        yMin = max(min(Ar(:, 2)), min(Br(:, 2)));
        yMax = min(max(Ar(:, 2)), max(Br(:, 2)));
        isOutside = litOutR(:, 2) <= yMin | litOutR(:, 2) >= yMax;
        outsideR = litOutR(isOutside, :);
        remainR = litOutR(~isOutside, :);
        fprintf('Non c1/c2 points: %d outside region (y outside [%.2f, %.2f]), %d remaining\n', ...
                size(outsideR, 1), yMin, yMax, size(remainR, 1));

        if PARAMS.SHOW_FIGURES == 1
            fig4 = figure('Name', sprintf('2D interpolation, rotated - view %d - curve pair (%d, %d)', PARAMS.VIEW_ID, pairId(1), pairId(2)), ...
                          'NumberTitle', 'off');
            ax4 = axes(fig4);
            hold(ax4, 'on');

            plot(ax4, [Ar(rung, 1), Br(rung, 1)]', [Ar(rung, 2), Br(rung, 2)]', '-', ...
                 'Color', [0.85 0.85 0.85], 'LineWidth', 0.5, 'HandleVisibility', 'off');
            for k = 2:numel(tVals) - 1
                t = tVals(k);
                P = (1 - t) * Ar + t * Br;
                scatter(ax4, P(:, 1), P(:, 2), 8, (1 - t) * [1 0 0] + t * [0 0.3 1], 'filled', ...
                        'HandleVisibility', 'off');
            end
            h41 = scatter(ax4, Ar(:, 1), Ar(:, 2), 22, [1 0 0], 'filled', ...
                          'DisplayName', sprintf('Curve 1 (id %d) edge points', pairId(1)));
            h42 = scatter(ax4, Br(:, 1), Br(:, 2), 22, [0 0.3 1], 'filled', ...
                          'DisplayName', sprintf('Curve 2 (id %d) edge points', pairId(2)));

            for k = 1:size(remainR, 1)
                yline(ax4, remainR(k, 2), ':', 'Color', [0.55 0.8 1], 'LineWidth', 0.5, ...
                      'HandleVisibility', 'off');
            end
            hLit4 = scatter(ax4, remainR(:, 1), remainR(:, 2), 24, [0 0.7 0], 'filled', ...
                            'MarkerEdgeColor', 'k', 'LineWidth', 0.5, ...
                            'DisplayName', sprintf('Lit, not on curve 1/2: %d', size(remainR, 1)));
            hOut4 = scatter(ax4, outsideR(:, 1), outsideR(:, 2), 24, [1 0.55 0], 'filled', ...
                            'MarkerEdgeColor', 'k', 'LineWidth', 0.5, ...
                            'DisplayName', sprintf('Outside region: %d', size(outsideR, 1)));
            xline(ax4, 0, '-', 'Color', [0.4 0.4 0.4], 'HandleVisibility', 'off');
            yline(ax4, 0, '-', 'Color', [0.4 0.4 0.4], 'HandleVisibility', 'off');

            axis(ax4, 'equal');
            set(ax4, 'YDir', 'normal', 'Box', 'on', 'XGrid', 'off', 'YGrid', 'off');
            xlabel(ax4, 'x (px, rotated)');
            ylabel(ax4, 'y (px, rotated)');
            title(ax4, sprintf('View %d: rotated so the longest end vector (%s end) lies on +x from the origin', ...
                  PARAMS.VIEW_ID, end_name(longIdx)));
            legend(ax4, [h41, h42, hLit4, hOut4], 'Location', 'southoutside', 'Orientation', 'horizontal');
            hold(ax4, 'off');
        end
        % ==================================================================
        % One figure per remaining green point (the ones with a dotted line):
        % the green point + the closest c1 / c2 point above and below its y
        % (closest in y), i.e. 5 points total.
        % ==================================================================
        isWithin = false(size(remainR, 1), 1);   % per green point: true = within region
        for k = 1:size(remainR, 1)
            g = remainR(k, :);
            [c1Above, c1Below] = nearest_above_below(Ar, g(2));
            [c2Above, c2Below] = nearest_above_below(Br, g(2));

            % Cross-product vectors, P = green point. The points are 2D, so they
            % are lifted to z = 0 and each d is a 3-vector [0 0 dz]; the sign of
            % dz says which side of the first edge the green point is on (NaN if a
            % point is missing). Pc = above, P̄c (P with a bar) = below the green
            % point's y, matching the figure labels.
            %   d1 = (Pc2  - Pc1)  x (P - Pc1)
            %   d2 = (Pc1  - P̄c1) x (P - P̄c1)
            %   d3 = (P̄c1 - P̄c2) x (P - P̄c2)
            %   d4 = (P̄c2 - Pc2)  x (P - Pc2)
            d1 = cross_xy(c2Above - c1Above, g - c1Above);
            d2 = cross_xy(c1Above - c1Below, g - c1Below);
            d3 = cross_xy(c1Below - c2Below, g - c2Below);
            d4 = cross_xy(c2Below - c2Above, g - c2Above);
            fprintf('Green point %d/%d (%.2f, %.2f):\n', k, size(remainR, 1), g(1), g(2));
            % "P with a bar on top" = P + combining overline (U+0305), so the
            % console matches the bar symbols in the figure.
            Pb = ['P' char(773)];
            fprintf('  d1 = (Pc2 - Pc1) x (P - Pc1) = [%.4f %.4f %.4f]\n', d1);
            fprintf('  d2 = (Pc1 - %sc1) x (P - %sc1) = [%.4f %.4f %.4f]\n', Pb, Pb, d2);
            fprintf('  d3 = (%sc1 - %sc2) x (P - %sc2) = [%.4f %.4f %.4f]\n', Pb, Pb, Pb, d3);
            fprintf('  d4 = (%sc2 - Pc2) x (P - Pc2) = [%.4f %.4f %.4f]\n', Pb, d4);

            % Classify the green point: all four d point the same way along z
            % (all into the page or all out of the page) -> within the region;
            % any mismatch -> outside. A zero dz (collinear) or NaN dz (a missing
            % Pc / P̄c point) is not a definite direction, so it counts as a mismatch.
            dz = [d1(3), d2(3), d3(3), d4(3)];
            isWithin(k) = all(dz > 0) || all(dz < 0);
            if isWithin(k)
                if dz(1) > 0, zDir = 'out of the page (+z)'; else, zDir = 'into the page (-z)'; end
                clsLabel = sprintf('WITHIN region (all 4 %s)', zDir);
            else
                clsLabel = 'OUTSIDE region (d1-d4 do not all share one z direction)';
            end
            fprintf('  -> %s\n', clsLabel);

            if PARAMS.SHOW_FIGURES == 1
                figK = figure('Name', sprintf('Green point %d/%d - y = %.2f', k, size(remainR, 1), g(2)), ...
                              'NumberTitle', 'off');
                axK = axes(figK);
                hold(axK, 'on');
                yline(axK, g(2), ':', 'Color', [0.55 0.8 1], 'LineWidth', 0.5, 'HandleVisibility', 'off');
                hK1a = scatter(axK, c1Above(1), c1Above(2), 40, [1 0 0], 'filled', 'DisplayName', '$P_{c1}$ (curve 1, above)');
                hK1b = scatter(axK, c1Below(1), c1Below(2), 40, [1 0 0], 'filled', 'DisplayName', '$\bar{P}_{c1}$ (curve 1, below)');
                hK2a = scatter(axK, c2Above(1), c2Above(2), 40, [0 0.3 1], 'filled', 'DisplayName', '$P_{c2}$ (curve 2, above)');
                hK2b = scatter(axK, c2Below(1), c2Below(2), 40, [0 0.3 1], 'filled', 'DisplayName', '$\bar{P}_{c2}$ (curve 2, below)');
                % labels next to the dots
                text(axK, c1Above(1), c1Above(2), '  $P_{c1}$', 'Interpreter', 'latex', 'Color', [1 0 0], 'FontWeight', 'bold');
                text(axK, c1Below(1), c1Below(2), '  $\bar{P}_{c1}$', 'Interpreter', 'latex', 'Color', [1 0 0], 'FontWeight', 'bold');
                text(axK, c2Above(1), c2Above(2), '  $P_{c2}$', 'Interpreter', 'latex', 'Color', [0 0.3 1], 'FontWeight', 'bold');
                text(axK, c2Below(1), c2Below(2), '  $\bar{P}_{c2}$', 'Interpreter', 'latex', 'Color', [0 0.3 1], 'FontWeight', 'bold');
                hKg = scatter(axK, g(1), g(2), 50, [0 0.7 0], 'filled', 'MarkerEdgeColor', 'k', ...
                              'DisplayName', 'Lit, not on curve 1/2');
                % zoom to just the (up to) 5 points, with a margin
                allK = [c1Above; c1Below; c2Above; c2Below; g];
                allK = allK(~any(isnan(allK), 2), :);
                lo = min(allK, [], 1);
                hi = max(allK, [], 1);
                % x and y are scaled independently (no 'axis equal') so the x range
                % hugs the points' x extent
                padX = 0.25 * max(hi(1) - lo(1), 1);
                padY = 0.25 * max(hi(2) - lo(2), 1);
                xlim(axK, [lo(1) - padX, hi(1) + padX]);
                ylim(axK, [lo(2) - padY, hi(2) + padY]);
                set(axK, 'YDir', 'normal', 'Box', 'on');
                xlabel(axK, 'x (px, rotated)');
                ylabel(axK, 'y (px, rotated)');
                title(axK, {sprintf('Green point (%.2f, %.2f) with nearest c1/c2 points above and below', g(1), g(2)), ...
                            sprintf('dz: d1 %.2f, d2 %.2f, d3 %.2f, d4 %.2f  ->  %s', ...
                                    d1(3), d2(3), d3(3), d4(3), clsLabel)});
                legend(axK, [hK1a, hK1b, hK2a, hK2b, hKg], 'Interpreter', 'latex', 'Location', 'southoutside', 'Orientation', 'horizontal');
                hold(axK, 'off');
            end
        end

        fprintf('Green points: %d within region, %d outside region (of %d)\n', ...
                nnz(isWithin), nnz(~isWithin), numel(isWithin));
        fprintf('After transform: longest vector [%.4f; %.4f] starts at the origin\n', endVecR(longIdx, :));

        resNotOnPair(r) = size(litOutR, 1);
        resAutoOutside(r) = size(outsideR, 1);
        resGreen(r) = numel(isWithin);
        resWithin(r) = nnz(isWithin);
        resOutside(r) = nnz(~isWithin);
        resStatus(r) = "ok";
    end
end
end

% ---- summary over all surfaces ----
results = table(resView, resName, resCurve1, resCurve2, resNotOnPair, resAutoOutside, ...
                resGreen, resWithin, resOutside, resStatus, ...
                'VariableNames', {'view', 'surface', 'curve1', 'curve2', 'notOnPair', 'autoOutside', ...
                                  'green', 'within', 'greenOutside', 'status'});
fprintf('\n===== Summary: %d surfaces x %d views =====\n', nSurf, nView);
disp(results);
fprintf('%d processed, %d skipped; %d green points within region in total\n', ...
        nnz(resStatus == "ok"), nnz(resStatus ~= "ok"), sum(resWithin, 'omitnan'));

% ---- save for Occlusion_2D_filter.m ----
% results columns used there: surface, view, green (points tested), within, status ("ok" = valid view)
if ~isempty(PARAMS.RESULTS_FILE)
    plyDir = PARAMS.PLY_DIR;
    save(PARAMS.RESULTS_FILE, 'results', 'plyDir');
    fprintf('Saved results table to %s\n', PARAMS.RESULTS_FILE);
end

function Q = rotate_points(Rot, P, origin)
%ROTATE_POINTS Translate N x 2 matrix dimension of points so origin is at (0,0), then rotate all
% of them at once: [X; Y] = Rot * [x; y], with x, y stacked as a 2 x N matrix.
XY = [P(:, 1)' - origin(1); P(:, 2)' - origin(2)];   % 2 x N  ([x; y])
Q = (Rot * XY)';                                      % back to N x 2
end

function c = cross_xy(u, v)
%CROSS_XY Cross product of two 2D vectors (1 x 2 each) lifted to z = 0, as a
% 1 x 3 vector [0 0 u_x*v_y - u_y*v_x].
c = cross([u(1:2), 0], [v(1:2), 0]);
end

function [pAbove, pBelow] = nearest_above_below(P, y0)
%NEAREST_ABOVE_BELOW Rows of P (N x 2) closest in y to y0 with y > y0 / y < y0.
% [NaN NaN] if the curve has no point on that side.
pAbove = [NaN NaN];
pBelow = [NaN NaN];
d = P(:, 2) - y0;
iA = find(d > 0);
iB = find(d < 0);
if ~isempty(iA)
    [~, m] = min(d(iA));
    pAbove = P(iA(m), :);
end
if ~isempty(iB)
    [~, m] = max(d(iB));
    pBelow = P(iB(m), :);
end
end

function s = end_name(idx)
%END_NAME Label for row idx of the end-point vectors (1 = start, 2 = finish).
names = {'start', 'finish'};
s = names{idx};
end

function set_pixel_axes(ax, imgSize)
%SET_PIXEL_AXES Labeled x / y pixel axes with ticks (no grid lines).
set(ax, 'Box', 'on', 'XGrid', 'off', 'YGrid', 'off', ...
        'XTick', 0:100:imgSize - 1, 'YTick', 0:100:imgSize - 1);
xlabel(ax, 'x (px)');
ylabel(ax, 'y (px)');
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
