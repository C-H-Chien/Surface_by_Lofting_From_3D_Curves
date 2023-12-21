close all;
clear;

import yaml.loadFile

%> Use object 00000325 as example, replace pathes to other objects for your
%usage.

%> curve points sampled from ABC dataset's parametrized representation
input_curves = load("curves.mat").curve_points;
%> yml file containing matrices of all the views
ymlPath = fullfile(pwd, "00000325/transforms_train.json");

data = yaml.loadFile(ymlPath);
view_matrix = data.frames;
K_view = {};
RT_view = {};
for i = 1:size(view_matrix, 2)
    %> get K
    tmp = view_matrix{i}.camera_intrinsics;
    K(1, :) = cell2mat(tmp{1});
    K(2, :) = cell2mat(tmp{2});
    K(3, :) = cell2mat(tmp{3});
    %> get RT
    tmp = view_matrix{i}.transform_matrix;
    RT(1, :) = cell2mat(tmp{1});
    RT(2, :) = cell2mat(tmp{2});
    RT(3, :) = cell2mat(tmp{3});
    RT(4, :) = cell2mat(tmp{4});
    
    K_view{end + 1} = K;
    RT_view{end + 1} = RT;
    
end


scale_min = [inf inf inf];
scale_max = [-inf -inf -inf];

for i = 1:size(input_curves, 2)
    c = input_curves{i};
    c_min = min(c);
    c_max = max(c);
    scale_min = min([scale_min; c_min]);
    scale_max = max([scale_max; c_max]);
end
%> calculate the scale factor. Using this factor to contain the object in a
%1 by 1 by 1 bounding box
factor = max([scale_max - scale_min]');
factor = 1/factor;
viewCnt = size(K_view, 2);
projection_matrix_by_view = {};

for i = 1:viewCnt
    %> image of the object from the view i
    imgPath = fullfile(pwd, "00000325/train_img/", sprintf("%d_colors.png", i - 1));
    %> the dataset's matrix is from camera to world. Use inverse to get the
    %matrix from world to camera
    trans = inv(RT_view{i});
    trans = trans(1:3, :);

    K = K_view{i};
    %> Before multiply K, let x be -x
    projMat = K * [-1 0 0; 0 1 0; 0 0 1] * trans;
    %> Using scale factor
    projMat(:, 1:3) = projMat(:, 1:3) .* factor;
    
    %> visualization. Curve points projection should overlap the edge of
    %the object 
    imshow(imread(imgPath));
    hold on;
    for j = 1:size(input_curves, 2)
        c = input_curves{j};
        c = [c'; ones(1, size(c, 1))];
        proj = projMat * c;
        proj = proj(1:2, :) ./ proj(3, :);
        plot(proj(1, :), proj(2, :));
        hold on
    end
    hold off;

    projection_matrix_by_view{end + 1} = projMat;
    disp(". ")
end
%> save the matrix converting result
save("./projection.mat", "projection_matrix_by_view");