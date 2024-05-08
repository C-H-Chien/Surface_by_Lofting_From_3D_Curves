close all;
clear;

import yaml.loadFile

%> Set 1 to Write_to_Projmatrix_Files is writing projection matrices as a 
%  series of .projmatrix files, if necessary. This is mainly used for multiview curve sketch
Write_to_Projmatrix_Files = 0;

%> Use object 00000325 as example, replace paths to other ABC dataset 
%  objects for your own usage.
dataset_path = "/home/chchien/datasets/ABC_NEF/";
object_tag_name = "00000568";

%> curve points sampled from ABC dataset's parametrized representation
input_curves = load(fullfile(dataset_path, object_tag_name, "curves.mat")).curve_points;

%> yml file containing matrices of all the views
ymlPath = fullfile(dataset_path, object_tag_name, "transforms_train.json");

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

%> Move all curve points to the first quatriple and scale up/down so that 
%  one of the axis is in the interval [0,1]
point_location_max = [-inf -inf -inf];
shift_curves = input_curves;
for i = 1:size(shift_curves, 2)
    c = shift_curves{i};
    c(:,1) = (c(:,1) - scale_min(1))*factor;
    c(:,2) = (c(:,2) - scale_min(2))*factor;
    c(:,3) = (c(:,3) - scale_min(3))*factor;
    shift_curves{i} = c;

    c_max = max(c);
    point_location_max = max([point_location_max; c_max]);
end

%> Shift the entire curve points to center at (0.5, 0.5)
figure;
final_curves = shift_curves;
for i = 1:size(final_curves, 2)
    displacement = 0.5 - (point_location_max ./ 2);
    c = final_curves{i};
    c(:,1) = c(:,1) + displacement(1);
    c(:,2) = c(:,2) + displacement(2);
    c(:,3) = c(:,3) + displacement(3);
    final_curves{i} = c;

    plot3(c(:, 1), c(:, 2), c(:, 3));
    hold on
end
hold off;
xlabel('x');
ylabel('y');
zlabel('z');
axis equal;

viewCnt = size(K_view, 2);
projection_matrix_by_view = {};

for i = 1:viewCnt
    %> image of the object from the view i
    imgPath = fullfile(dataset_path, object_tag_name, "/train_img/", sprintf("%d_colors.png", i - 1));
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
    imshow(imread(imgPath));
    hold on;
    for j = 1:size(final_curves, 2)
        c = final_curves{j};
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
% save_path = fullfile(mfiledir, "projection.mat");
% save(save_path, "projection_matrix_by_view");

if Write_to_Projmatrix_Files == 1
    for i = 1:length(projection_matrix_by_view)
        proj_matrix = projection_matrix_by_view{i};
        path = fullfile(mfiledir, "projmatrix", sprintf("%d_colors.projmatrix", i - 1));
        writematrix(proj_matrix, path, "FileType", "text", "Delimiter", " ");
    end
end

