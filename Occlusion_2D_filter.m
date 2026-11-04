% Occlusion_2D_filter: decide which lofted surfaces to filter out, using the
% results saved by Cross_Rotation_point_validation.m (nothing is recomputed
% here). The filtered-out .ply files are then deleted from the source folder
% (tmp/filtered_surfaces), so that folder is updated in place.
%
% Per (view, surface) row:   frac = within / green   (points inside the interpolated
%                                                     region / points tested)
%   - only rows with status "ok" count (views with < 2 c1/c2 points are skipped)
%   - green == 0 -> frac = 0 (nothing was inside, so nothing against the surface)
% Per surface:               score = median of frac over its valid views
% Threshold:                 Otsu on the scores of all surfaces (adaptive, no fixed number)
% Filtered out:              score > threshold, but only if the scores really split
%                            into two groups (separability >= MIN_SEPARABILITY)
% Surfaces with no valid view are "undecided" and are kept.

% ---- settings ----
PARAMS.RESULTS_FILE = fullfile(pwd, 'tmp', 'cross_rotation_results.mat');
PARAMS.N_BINS = 64;             % histogram bins for Otsu
PARAMS.MIN_SURFACES = 5;         % fewer decided surfaces than this -> no filtering
PARAMS.MIN_SEPARABILITY = 0.5;   % Otsu separability (0..1) needed to trust the threshold
PARAMS.THRESH_SCALE = 1.0;      % >1 = stricter: final threshold = Otsu threshold * THRESH_SCALE
PARAMS.MIN_SCORE = 0;         % absolute floor: never filter a surface whose score (fraction of
                                 % tested points inside its region) is <= this, whatever Otsu says

% ---- load ----
S = load(PARAMS.RESULTS_FILE);
results = S.results;
fprintf('Loaded %d (view, surface) rows from %s\n', height(results), PARAMS.RESULTS_FILE);

% ---- per (view, surface) fraction, valid views only ----
isValid = results.status == "ok";
frac = zeros(height(results), 1);
hasPts = isValid & results.green > 0;
frac(hasPts) = results.within(hasPts) ./ results.green(hasPts);

% ---- per-surface score = median fraction over valid views ----
surfNames = unique(results.surface, 'stable');
nS = numel(surfNames);
score = nan(nS, 1);
nValid = zeros(nS, 1);
for i = 1:nS
    rows = isValid & results.surface == surfNames(i);
    nValid(i) = nnz(rows);
    if nValid(i) > 0
        score(i) = median(frac(rows));
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

% ---- report ----
fprintf('\n===== Surfaces to FILTER OUT (%d of %d) =====\n', nnz(filtered), nS);
idx = find(filtered);
[~, ord] = sort(score(idx), 'descend');
idx = idx(ord);
for k = 1:numel(idx)
    fprintf('  %-40s score = %.4f  (%d valid views)\n', surfNames(idx(k)), score(idx(k)), nValid(idx(k)));
end
fprintf('Kept: %d surfaces (%d undecided)\n', nS - nnz(filtered), nnz(~decided));

% ---- update the source folder (tmp/filtered_surfaces) in place ----
% kept = every .ply in the source folder that was not labelled "filter out"
% (undecided surfaces, and any .ply not covered by the saved results, are kept).
% The filtered-out .ply files are deleted from the source folder, so it ends up
% holding exactly the kept surfaces.
srcDir = S.plyDir;
allPly = dir(fullfile(srcDir, '*.ply'));
keepMask = ~ismember(string({allPly.name})', surfNames(filtered));
keepPly = allPly(keepMask);
dropPly = allPly(~keepMask);
for k = 1:numel(dropPly)
    delete(fullfile(dropPly(k).folder, dropPly(k).name));
end
fprintf('Updated %s: removed %d filtered .ply, %d kept (of %d).\n', srcDir, numel(dropPly), numel(keepPly), numel(allPly));
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
