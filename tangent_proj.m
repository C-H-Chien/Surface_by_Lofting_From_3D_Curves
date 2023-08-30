clear;
close all;

preProcessedCurves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves;

cnt = 7;
curve = preProcessedCurves.points{cnt};
tangent = preProcessedCurves.tangents{cnt};
fname1 = sprintf( "./data/amsterdam-house-full/%02d.projmatrix", cnt );

scatter3(curve(:, 1), curve(:,2), curve(:,3), 2, 'blue');
hold on;
pick_ci = 2000;
point = curve(pick_ci,:);
vector = tangent(pick_ci,:);
quiver3(point(1), point(2), point(3), ...
        vector(1), vector(2), vector(3), 'color', 'g', 'AutoScaleFactor', 1, 'LineWidth', 1);

scatter3(point(1), point(2), point(3), 100, 'red', 'filled');
scatter3(point(1) + vector(1), point(2) + vector(2), point(3) + vector(3), 100, 'red', 'filled')

projMatrix = load(fname1);
[K, RT] = Pdecomp(projMatrix);
R = RT(1:3,1:3);
T = RT(1:3, 4);

% to camera
figure;
cc = (RT * [curve'; ones(1, size(curve, 1))])';
cp = (RT * [point 1]')';
cve = (RT * [point + vector 1]')';
cv = (cve - cp) / norm((cve - cp));

scatter3(cc(:, 1), cc(:, 2), cc(:, 3), 2,'blue', 'filled');
hold on;
scatter3(cp(1), cp(2), cp(3), 100,'red', 'filled');
scatter3(cve(1), cve(2), cve(3), 100,'red', 'filled');
scatter3(0, 0, 0, 100, 'cyan', 'filled');
quiver3(cp(1), cp(2), cp(3), ...
        cv(1), cv(2), cv(3), 'color', 'g', 'AutoScaleFactor', 1, 'LineWidth', 1);

% to image
ic = (K * cc');
ic = ic ./ ic(3, :);
ip = K * cp';
ip = ip ./ ip(3);
ive = K * cve';
ive = ive ./ ive(3);
iv = (ive - ip) / norm((ive - ip));
figure;
scatter(ic(1, :), ic(2, :), 2, 'blue');
hold on;
scatter(ip(1, :), ip(2, :), 100, 'red', 'filled');
scatter(ive(1, :), ive(2, :), 100, 'red', 'filled');
quiver(ip(1), ip(2), ...
        iv(1), iv(2), 'color', 'g', 'AutoScaleFactor', norm(ive - ip), 'LineWidth', 1);

% direct
addpath("./util");
pc = projMatrix * [curve ones(size(curve, 1), 1)]';
pc = pc(1:2, :) ./ pc(3, :);
pte = projMatrix * [curve + tangent ones(size(curve, 1), 1)]';
pte = pte(1:2, :) ./ pte(3, :);
res = pte - pc;
res = res ./ sqrt(sum(res .^ 2, 1));

isequal(res, tangent_projection(curve, tangent, projMatrix));
figure;
scatter(pc(1, :), pc(2, :), 2, 'blue');
hold on;
scatter(pc(1, pick_ci), pc(2, pick_ci), 100, 'res', 'filled');
scatter(pte(1, pick_ci), pte(2, pick_ci), 100, 'red', 'filled');
quiver(pc(1, pick_ci), pc(2, pick_ci), ...
        res(1, pick_ci), res(2, pick_ci), 'color', 'g', 'AutoScaleFactor', norm(ive - ip), 'LineWidth', 1);