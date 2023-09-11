clear;
% res = {};
% view = 0;
% 
% 
% while 1
%     try
%         res{view + 1} = load(fullfile(pwd, 'tmp', 'res', sprintf("view %d.mat", view))).res; 
%         view = view + 1;
%     catch
%         break;
%     end
% end
% 

% res = load("./tmp/view 0.mat").res;
% 
% cnt1 = sum(res{5} == 1, 'all');
% cnt0 = sum(res{5} == 0, 'all');
% 
% evidence = load("./tmp/evidence in view 0.mat").evidence_by_view;
if ~exist(fullfile(pwd, 'tmp', 'res', 'res_surface'), 'dir')
   mkdir(fullfile(pwd, 'tmp', 'res', 'res_surface'));
end
view = 0;
res = {};
while 1
    try
        tmp = load(fullfile(pwd, 'tmp', 'res', sprintf("evidence in view %d", view))).evidence_by_view;
        view = view + 1;
    catch
        break;
    end
    res{view} = tmp;
end
surfaceCnt = size(res{1}, 2);

counter = zeros(surfaceCnt, 1);

for i = 1:50
    for k = 1:surfaceCnt
        if res{i}{k}(1) / res{i}{k}(2) > 0.3
            counter(k) = counter(k) + 1;
        end
    end
end

pairs = load("./tmp/pairs_after_curvature_filter.mat").pairs_after_curvature_filter;
manual_pick = load('./data/manual_pick.mat').manual_pick;
matchCnt = 0;
selected = [];

for i = 1:surfaceCnt
    if counter(i) < 5
        c1 = pairs(i, 1);
        c2 = pairs(i, 2);
        selected = [selected; c1 c2];
        surfaceName = fullfile(pwd, 'blender', 'output', "loftsurf_" + int2str(c1) + "_" + int2str(c2) + "_");
        if pairs(i, 3) == 1
            surfaceName = surfaceName + "normal.ply";
        else
            surfaceName = surfaceName + "reverse.ply";
        end
        copyfile(surfaceName, fullfile(pwd, 'tmp', 'res', 'res_surface'));
        for k = 1:size(manual_pick, 1)
            if manual_pick(k, 1) == c1 && manual_pick(k, 2) == c2
                matchCnt = matchCnt + 1;
            end
        end
    end
end





