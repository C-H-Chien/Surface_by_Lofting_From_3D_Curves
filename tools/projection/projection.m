close all;
clear;

import yaml.loadFile

%> Set 1 to Write_to_Projmatrix_Files is writing projection matrices as a 
%  series of .projmatrix files, if necessary.
Write_to_Projmatrix_Files = 1;
Visualize_3D_Curve_Projection = 0;

%> Use object 00000325 as example, replace paths to other ABC dataset 
%  objects for your own usage.
media_storage = "/media/chchien/843557f5-9293-49aa-8fb8-c1fc6c72f7ea/";
dataset_name = "ABC-NEF";
dataset_path = strcat(media_storage, "/home/chchien/datasets/", dataset_name);
object_tag_name = "00000325";

%> curve points sampled from ABC dataset's parametrized representation.
%  Only used to see the projection of the 3D curves onto the images.
if Visualize_3D_Curve_Projection == 1
    curve_graph_file_name = strcat("complete_curve_graph_", object_tag_name, ".mat");
    final_curves = load(fullfile(pwd, "data", dataset_name, object_tag_name, curve_graph_file_name)).complete_curve_graph;
end

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
    %  the object 
    if Visualize_3D_Curve_Projection == 1
        imshow(imread(imgPath));
        hold on;
        for j = 1:size(final_curves, 2)
            c = final_curves{j};
            c = [c'; ones(1, size(c, 1))];
            proj = projMat * c;
            proj = proj(1:2, :) ./ proj(3, :);
            plot(proj(1, :)+1, proj(2, :)+1);
            hold on
        end
        hold off;
    end

    projection_matrix_by_view{end + 1} = projMat;
end

%> save the matrix converting results
if Write_to_Projmatrix_Files == 1
    write_folder_path = fullfile(pwd, "data", dataset_name, object_tag_name);
    if ~exist(fullfile(write_folder_path, 'projection_matrix'), 'dir')
        mkdir(fullfile(write_folder_path, 'projection_matrix'))
    end
    for i = 1:length(projection_matrix_by_view)
        proj_matrix = projection_matrix_by_view{i};
        file_name = strcat(sprintf('%02d', double(i-1)), ".projmatrix");
        file_write_path = fullfile(write_folder_path, "projection_matrix", file_name);
        writematrix(proj_matrix, file_write_path, "FileType", "text", "Delimiter", " ");
    end
end

