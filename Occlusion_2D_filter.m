% Occlusion_2D_filter: decide which lofted surfaces to filter out, using the
% results saved by Cross_Rotation_point_validation.m (nothing is recomputed
% here). The .ply surfaces in tmp/surfaces_after_curvature_filter (written by
% gaussian_curvature_filter) are first copied into tmp/filtered_surfaces; the
% surfaces marked "filter out" are then deleted from that copy.
%
% Per (view, surface) row:   dens = 1000 * within / regionArea
%                                   (GT 2D edge points inside the interpolated region,
%                                    per 1000 px^2 of region area)
%   - independent of how many other points the view has (no grid / y-slab dependence)
%   - only rows with status "ok" count (views with < 2 c1/c2 points are skipped)
%   - regionArea ~ 0 -> dens = 0 (degenerate region, nothing inside)
% Per surface:               score = median of dens over its valid views
% Threshold:                 Otsu on the scores of all surfaces (adaptive, no fixed number)
% Filtered out:              score > threshold, but only if the scores really split
%                            into two groups (separability >= MIN_SEPARABILITY)
% Surfaces with no valid view are "undecided" and are kept.

% ---- settings ----
PARAMS.RESULTS_FILE = fullfile(pwd, 'tmp', 'cross_rotation_results.mat');
if exist('RESULTS_FILE_OVERRIDE', 'var') && ~isempty(RESULTS_FILE_OVERRIDE)   % set by long_run.m to read NO_GRID_METHOD.m's results
    PARAMS.RESULTS_FILE = RESULTS_FILE_OVERRIDE;
end
PARAMS.SHOW_HISTOGRAM = false;   % true = show the Otsu histogram figure, false = skip it
PARAMS.N_BINS = 64;            % histogram bins for Otsu
PARAMS.MIN_SURFACES = 5;         % fewer decided surfaces than this -> no filtering
PARAMS.MIN_SEPARABILITY = 0.5;   % Otsu separability (0..1) needed to trust the threshold
PARAMS.THRESH_SCALE = 1.0;      % >1 = stricter: final threshold = Otsu threshold * THRESH_SCALE
PARAMS.MIN_SCORE = 0;         % absolute floor: never filter a surface whose score (density of
                                 % points inside its region) is <= this, whatever Otsu says

% ---- load ----
S = load(PARAMS.RESULTS_FILE);
results = S.results;
fprintf('Loaded %d (view, surface) rows from %s\n', height(results), PARAMS.RESULTS_FILE);

% ---- per (view, surface) fraction, valid views only ----
isValid = results.status == "ok";
if ~ismember('regionArea', results.Properties.VariableNames)
    error('Occlusion_2D_filter:noArea', ...
          'results has no regionArea column: re-run Cross_Rotation_point_validation / NO_GRID_METHOD first.');
end
PARAMS.AREA_UNIT = 1000;         % density is reported per this many px^2 (Otsu is scale-invariant)
PARAMS.SCORE_MODE = 'ratio';      % 'ratio'   = within / green (points tested)  [original]
                                 % 'density' = 1000 * within / regionArea
                                 % 'count'   = within (number of points inside the region; many = bad)
PARAMS.VIEW_AGG = 'median';        % how a surface combines its valid views: 'sum' or 'median'
frac = zeros(height(results), 1);   % per-row score
switch PARAMS.SCORE_MODE
    case 'ratio'
        hasPts = isValid & results.green > 0;
        frac(hasPts) = results.within(hasPts) ./ results.green(hasPts);
    case 'count'
        frac(isValid) = results.within(isValid);
    case 'density'
        hasArea = isValid & results.regionArea > 1e-6;
        frac(hasArea) = PARAMS.AREA_UNIT * results.within(hasArea) ./ results.regionArea(hasArea);
    otherwise
        error('Unknown PARAMS.SCORE_MODE "%s"', PARAMS.SCORE_MODE);
end
fprintf('Score mode: %s, view aggregation: %s\n', PARAMS.SCORE_MODE, PARAMS.VIEW_AGG);

% ---- per-surface score = VIEW_AGG ('sum' or 'median') of the per-view scores over valid views ----
surfNames = unique(results.surface, 'stable');
nS = numel(surfNames);
score = nan(nS, 1);
nValid = zeros(nS, 1);
for i = 1:nS
    rows = isValid & results.surface == surfNames(i);
    nValid(i) = nnz(rows);
    if nValid(i) > 0
        if strcmp(PARAMS.VIEW_AGG, 'sum')
            score(i) = sum(frac(rows));
        else
            score(i) = median(frac(rows));
        end
    end
end
decided = ~isnan(score);
fprintf('%d surfaces: %d with >= 1 valid view, %d undecided (no valid view, kept)\n', ...
        nS, nnz(decided), nnz(~decided));

% ---- Otsu threshold on the scores ----
filtered = false(nS, 1);
thr = NaN;
eta = NaN;
sc = score(decided);
if numel(sc) < PARAMS.MIN_SURFACES
    fprintf('Only %d decided surfaces (< %d): not enough to estimate a threshold, nothing filtered.\n', ...
            numel(sc), PARAMS.MIN_SURFACES);
elseif max(sc) - min(sc) < 1e-12
    fprintf('All scores are identical (%.4f): nothing to separate, nothing filtered.\n', sc(1));
else
    [thr, eta] = otsu_threshold(sc, PARAMS.N_BINS);
    fprintf('Otsu threshold on score = %.4f, separability = %.3f (needs >= %.2f)\n', ...
            thr, eta, PARAMS.MIN_SEPARABILITY);
    if eta >= PARAMS.MIN_SEPARABILITY
        thrFinal = max(thr * PARAMS.THRESH_SCALE, PARAMS.MIN_SCORE);
        fprintf('Final threshold = max(Otsu * %.2f, floor %.2f) = %.4f\n', ...
                PARAMS.THRESH_SCALE, PARAMS.MIN_SCORE, thrFinal);
        filtered = decided & score > thrFinal;
    else
        fprintf('Scores do not split into two clear groups: nothing filtered.\n');
    end
end

% ---- visualize the score histogram used by Otsu ----
if PARAMS.SHOW_HISTOGRAM && ~isempty(sc)
    figure('Name', 'Otsu histogram of surface scores', 'Color', 'w');
    if max(sc) - min(sc) < 1e-12
        edgesVis = sc(1) + [-0.5 0.5] * 0.01;   % degenerate case: one bin
    else
        edgesVis = linspace(min(sc), max(sc), PARAMS.N_BINS + 1);   % same bins as otsu_threshold
    end
    cntVis = histcounts(sc, edgesVis);
    ctrVis = (edgesVis(1:end-1) + edgesVis(2:end)) / 2;
    b = bar(ctrVis, cntVis, 1, 'FaceColor', [0.30 0.55 0.85], 'EdgeColor', 'w');
    hold on;
    % count label above every non-empty bin
    nz = cntVis > 0;
    text(ctrVis(nz), cntVis(nz), string(cntVis(nz)), 'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'bottom', 'FontSize', 8, 'Color', 'k');
    yl = ylim; ylim([0, yl(2) * 1.12]); yl = ylim;
    legEntries = b; legNames = {'score histogram'};
    if ~isnan(thr)
        hO = plot([thr thr], yl, 'r--', 'LineWidth', 1.8);
        text(thr, yl(2), sprintf(' Otsu = %.4f', thr), 'Color', [0.8 0 0], ...
             'VerticalAlignment', 'top', 'FontWeight', 'bold');
        legEntries(end+1) = hO; legNames{end+1} = sprintf('Otsu threshold (%.4f)', thr);
        if eta >= PARAMS.MIN_SEPARABILITY
            thrF = max(thr * PARAMS.THRESH_SCALE, PARAMS.MIN_SCORE);
            if abs(thrF - thr) > 1e-12
                hF = plot([thrF thrF], yl, 'm-', 'LineWidth', 1.8);
                legEntries(end+1) = hF; legNames{end+1} = sprintf('final threshold (%.4f)', thrF);
            end
        end
    end
    xlabel('surface score (median points per 1000 px^2 inside region, valid views)');
    ylabel('number of surfaces');
    title(sprintf('Otsu on surface scores: %d surfaces, %d bins, separability = %.3f (needs >= %.2f)', ...
          numel(sc), PARAMS.N_BINS, eta, PARAMS.MIN_SEPARABILITY));
    style_light(gca, legend(legEntries, legNames, 'Location', 'best'));
    drawnow;
end

% ---- report ----
fprintf('\n===== Surfaces to FILTER OUT (%d of %d) =====\n', nnz(filtered), nS);
idx = find(filtered);
[~, ord] = sort(score(idx), 'descend');
idx = idx(ord);
for k = 1:numel(idx)
    fprintf('  %-40s score = %.4f  (%d valid views)\n', surfNames(idx(k)), score(idx(k)), nValid(idx(k)));
end
fprintf('Kept: %d surfaces (%d undecided)\n', nS - nnz(filtered), nnz(~decided));

fprintf('\n===== UNDECIDED surfaces (no valid view, kept) (%d of %d) =====\n', nnz(~decided), nS);
for i = find(~decided)'
    st = unique(results.status(results.surface == surfNames(i)))';
    fprintf('  %-40s statuses: %s\n', surfNames(i), strjoin(st, ', '));
end

% ---- copy the post-curvature surfaces into tmp/filtered_surfaces, then drop the marked ones ----
% kept = every .ply in the source folder that was not labelled "filter out"
% (undecided surfaces, and any .ply not covered by the saved results, are kept).
srcDir = fullfile(pwd, 'tmp', 'surfaces_after_curvature_filter');
outDir = fullfile(pwd, 'tmp', 'filtered_surfaces');
if exist(outDir, 'dir')
    rmdir(outDir, 's');
end
mkdir(outDir);
allPly = dir(fullfile(srcDir, '*.ply'));
for k = 1:numel(allPly)
    copyfile(fullfile(srcDir, allPly(k).name), fullfile(outDir, allPly(k).name));
end
keepMask = ~ismember(string({allPly.name})', surfNames(filtered));
keepPly = allPly(keepMask);
dropPly = allPly(~keepMask);
for k = 1:numel(dropPly)
    delete(fullfile(outDir, dropPly(k).name));
end
fprintf('Copied %d .ply from %s to %s, removed %d filtered, %d kept.\n', numel(allPly), srcDir, outDir, numel(dropPly), numel(keepPly));
notEvaluated = ~ismember(string({allPly.name})', surfNames);
if any(notEvaluated)
    fprintf('Note: %d .ply in the source folder were not in the results file (kept without evaluation).\n', nnz(notEvaluated));
end

function [thr, eta] = otsu_threshold(x, nBins)
%OTSU_THRESHOLD Otsu's threshold for a 1-D sample x.
% thr = value splitting x into low / high groups (x > thr is the high group).
% eta = between-class variance / total variance (0..1), how well x splits in two.
edges = linspace(min(x), max(x), nBins + 1);
cnt = histcounts(x, edges);
p = cnt / sum(cnt);
ctr = (edges(1:end-1) + edges(2:end)) / 2;
w0 = cumsum(p);                  % weight of the low group if the cut is after bin k
w1 = 1 - w0;
m = cumsum(p .* ctr);            % cumulative mean
mT = m(end);
sigB = nan(1, nBins);
ok = w0 > 0 & w1 > 0;
sigB(ok) = (mT * w0(ok) - m(ok)).^2 ./ (w0(ok) .* w1(ok));
best = max(sigB);
k = round(mean(find(sigB == best)));   % middle of a tie plateau
thr = edges(k + 1);
sigT = sum(p .* (ctr - mT).^2);
eta = best / sigT;
end

function style_light(ax, lg)
%STYLE_LIGHT force a light theme so text is readable even with a dark MATLAB/IDE theme.
set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'GridColor', [0.4 0.4 0.4]);
set(ax.XLabel, 'Color', 'k'); set(ax.YLabel, 'Color', 'k'); set(ax.Title, 'Color', 'k');
set(lg, 'TextColor', 'k', 'Color', 'w', 'EdgeColor', 'k');
grid(ax, 'on'); box(ax, 'on');
end
