close all;
clear;

import yaml.loadFile

%> Set 1 to Write_to_Projmatrix_Files is writing projection matrices as a 
%  series of .projmatrix files, if necessary. This is mainly used for multiview curve sketch
Write_to_Projmatrix_Files = 1;

%> Use object 00000325 as example, replace paths to other ABC dataset 
%  objects for your own usage.
object_tag_name = "00002211";

%> curve points sampled from ABC dataset's parametrized representation
% input_curves = load("curves.mat").curve_points;

%> yml file containing matrices of all the views
mfiledir = "/home/chchien/datasets/ABC_NEF/";
ymlPath = fullfile(mfiledir, object_tag_name, "transforms_train.json");

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

viewCnt = size(K_view, 2);
projection_matrix_by_view = {};

for i = 1:viewCnt
    %> image of the object from the view i
    % imgPath = fullfile(mfiledir, object_tag_name, "/train_img/", sprintf("%d_colors.png", i - 1));
    %> the dataset's matrix is from camera to world. Use inverse to get the
    %matrix from world to camera
    trans = inv(RT_view{i});
    trans = trans(1:3, :);

    K = K_view{i};
    %> Before multiply K, let x be -x
    projMat = K * [-1 0 0; 0 1 0; 0 0 1] * trans;
    %> Using scale factor
    % projMat(:, 1:3) = projMat(:, 1:3) .* factor;
    
    %> visualization. Curve points projection should overlap the edge of
    %the object 
    % imshow(imread(imgPath));
    % hold on;
    % for j = 1:size(input_curves, 2)
    %     c = input_curves{j};
    %     c = [c'; ones(1, size(c, 1))];
    %     proj = projMat * c;
    %     proj = proj(1:2, :) ./ proj(3, :);
    %     plot(proj(1, :), proj(2, :));
    %     hold on
    % end
    % hold off;

    projection_matrix_by_view{end + 1} = projMat;
    fprintf("-");
end
fprintf("\n");

%> save the matrix converting result
% save_path = fullfile(mfiledir, "projection.mat");
% save(save_path, "projection_matrix_by_view");

if Write_to_Projmatrix_Files == 1
    for i = 1:length(projection_matrix_by_view)
        proj_matrix = projection_matrix_by_view{i};
        path = fullfile(mfiledir, object_tag_name, "train_img", sprintf("%d_colors.projmatrix", i - 1));
        writematrix(proj_matrix, path, "FileType", "text", "Delimiter", " ");
    end
end

