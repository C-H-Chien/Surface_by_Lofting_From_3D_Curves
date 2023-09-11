clear;
close all;

preProcessedCurves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves;

curve_num = 31;
cnt = 0;
no_align = 0;
for view = 0:0
    clf
    curve = preProcessedCurves.points{curve_num};
    tangent = preProcessedCurves.tangents{curve_num};
    
    fname1 = sprintf( "./data/amsterdam-house-full/%02d.projmatrix", view );
    projMatrix = load(fname1);
    [K, RT] = Pdecomp(projMatrix);
    R = RT(1:3,1:3);
    T = RT(1:3, 4);
    pick_ci = 2000;
    tt = tangent_projection(curve, tangent, projMatrix);
    
    % direct
    addpath("./util");
    pc = projMatrix * [curve ones(size(curve, 1), 1)]';
    pc = pc(1:2, :) ./ pc(3, :);
    pte = projMatrix * [curve + tangent ones(size(curve, 1), 1)]';
    pte = pte(1:2, :) ./ pte(3, :);
    res = pte - pc;
    res = res ./ sqrt(sum(res .^ 2, 1));
    
    % isequal(res, tangent_projection(curve, tangent, projMatrix));
    % figure;
    % scatter(pc(1, :), pc(2, :), 2, 'blue');
    hold on;
    scatter(pc(1, pick_ci), pc(2, pick_ci), 100, 'res', 'filled');
    scatter(pte(1, pick_ci), pte(2, pick_ci), 100, 'red', 'filled');
    quiver(pc(1, pick_ci), pc(2, pick_ci), ...
            res(1, pick_ci), res(2, pick_ci), 'color', 'magenta', 'AutoScaleFactor', norm(pc(:, pick_ci) - pte(:, pick_ci)), 'LineWidth', 1);
    
    
    
    
    
    fname1 = sprintf( "./data/amsterdam-house-full/%02d.projmatrix", view );
    fname2 = sprintf( "./data/TO_Edges_Amsterdam_House/%02d.mat", view );
    fname3 = sprintf( "./data/amsterdam-house-full/%02d.jpg", view );
    edge = load(fname2).TO_edges;
    pic = imread(fname3);
    map = zeros(size(pic, 1), size(pic, 2));
    for i = 1:size(edge, 1)
        pos_x = floor(edge(i, 1) + 1);
        pos_y = floor(edge(i, 2) + 1);
        map(pos_y, pos_x) = 1;
    end
    % figure;
    % imshow(double(map));
    scatter(edge(:, 1), edge(:, 2), 1, "green");
    dis = sqrt(sum((edge(:, 1:2) - pc(:, pick_ci)') .^ 2, 2));
    [minDis, idx] = min(dis);
    scatter(edge(idx, 1), edge(idx, 2), 100, 'black');
    theta = edge(idx, 3);
    vec = [cos(theta) sin(theta)];
    vec_proj = [res(1, pick_ci), res(2, pick_ci)];
    quiver(edge(idx, 1), edge(idx, 2), ...
            vec(1), vec(2), 'color', 'cyan', 'AutoScaleFactor', norm(pc(:, pick_ci) - pte(:, pick_ci)), 'LineWidth', 1);
    set(gca, 'YDir', 'reverse');
    
    hold off;
    if minDis > 3
        disp("no align")
        title("no align");
        saveas(gcf,fullfile(pwd, 'tmp', 'fig', "view" + int2str(view) + ".png"));
        no_align = no_align + 1;
        continue;
    end
    
    diff = acos(sum(vec .* vec_proj) / (norm(vec) * norm(vec_proj)));
    title(sprintf("Degree diff: %f deg", rad2deg(diff)));
    disp(rad2deg(diff));
    if rad2deg(diff) < 10 || (180 - rad2deg(diff) < 10)
        cnt = cnt + 1;
    end
    % saveas(gcf,fullfile(pwd, 'tmp', 'fig', "view" + int2str(view) + ".png"));
end