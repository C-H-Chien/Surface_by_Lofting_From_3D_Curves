%> Third-Order Edge Detector Credit:
%> Paper: Kimia, Benjamin B., Xiaoyan Li, Yuliang Guo, and Amir Tamrakar. 
%         "Differential geometry in edge detection: accurate estimation of 
%         position, orientation and curvature." IEEE transactions on 
%         pattern analysis and machine intelligence 41, no. 7 (2018): 
%         1573-1586.
%> Implementations: (1) https://github.com/yuliangguo/Differential_Geometry_in_Edge_Detection
%                   (2) https://github.com/C-H-Chien/Third-Order-Edge-Detector

% mfiledir = fileparts(mfilename('fullpath'));
Dataset_Path = '/media/chchien/843557f5-9293-49aa-8fb8-c1fc6c72f7ea/home/chchien/datasets/';
Dataset_Name = 'ABC-NEF/';      %> ABC-NEF, DTU
Scene_Name = '00000325/';          %> 00009779
Image_Folder_Name = 'train_img/';   %> train_img, color
postfix = '.png';               %> .png for ABC-NEF, .jpg for Replica
All_Images = dir(strcat(Dataset_Path, Dataset_Name, Scene_Name, Image_Folder_Name, '*', postfix));
Full_Accessible_Path = [Dataset_Path, Dataset_Name, Scene_Name, Image_Folder_Name];

Save_TO_Edges_as_Files  = 1;
file_extension          = ".mat";

%> Settings for the Third-Order Edge Detector
thresh = 1;
sigma = 1;
n = 1;
format long;

for i = 1:size(All_Images, 1)
    src_Data_Path = strcat(Dataset_Path, Dataset_Name, Scene_Name, Image_Folder_Name, All_Images(i).name);
    img_ = imread(src_Data_Path);
    img_ = double(rgb2gray(img_));
    [TO_edges, ~, ~, ~] = third_order_edge_detector(img_, sigma, n, thresh, 1);
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % outputs of *third_order_edge_detector*
    % TO_edges = [Subpixel_X Subpixel_Y Orientation Confidence]
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    TO_Edges_Name = extractBefore(All_Images(i).name, postfix);
    yy = find(TO_edges(:,1) < 10 | TO_edges(:,2) > size(img_,1)-10 | TO_edges(:,2) < 10 | TO_edges(:,1) > size(img_,2)-10);
    TO_edges(yy,:) = [];

    %> Omit the last column (which is the gradient magnitude and we don't need it)
    TO_edges(:, end) = [];

    %> Save as .edg file
    % save_edg([Full_Accessible_Path, TO_Edges_Name, '.edg'], TO_edges, [size(img_, 1), size(img_, 2)]);

    %> Save as .txt file
    if Save_TO_Edges_as_Files == 1
        %> create a folder `edges`
        write_folder_path = fullfile(pwd, "data", Dataset_Name, Scene_Name);
        if ~exist(fullfile(write_folder_path, 'edges'), 'dir')
            mkdir(fullfile(write_folder_path, 'edges'))
        end
        img_index               = extractBefore(string(All_Images(i).name), "_");
        img_index_padded_str    = sprintf('%02d', double(img_index));
        output_edges_file_name  = strcat("edges_", img_index_padded_str, file_extension);
        file_save_path          = fullfile(write_folder_path, "edges", output_edges_file_name);
        if file_extension == ".mat"
            save(file_save_path, "TO_edges");
        elseif file_extension == ".txt"
            writematrix(TO_edges, file_save_path, 'Delimiter', 'tab');
        end
    end
    
    %> Monitor the progress
    fprintf(". ");

    % figure(1);
    % src_Data_Path = strcat(Full_Accessible_Path, All_Images(i).name);   %> 01.jpg
    % img_ = imread(src_Data_Path);
    % img_ = double(rgb2gray(img_));
    % imshow(uint8(img_)); hold on;
    % plot(TO_edges(:,1), TO_edges(:,2), 'c.');

end
fprintf("\n");

%% 
%> An Example of super-imposing third-order edges on an image
figure;
src_Data_Path = strcat(Full_Accessible_Path, All_Images(2).name);   %> 01.jpg
img_ = imread(src_Data_Path);
img_ = double(rgb2gray(img_));
[TO_edges, ~, ~, ~] = third_order_edge_detector(img_, sigma, n, 8, 1);
% imshow(uint8(img_)); hold on;
canvas = zeros(size(img_));
imshow(uint8(canvas)); hold on;
plot(TO_edges(:,1), TO_edges(:,2), 'c.', 'MarkerSize', 2);
