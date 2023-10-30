clear all; close all;

%> Code Description: 
%     Visualize and fetch topological contour graph (TCG) fragments
%     information from .cem files.
%
%> Required functions:
%     - read_cem_files.m
%     - visualize_contour_groups.m
%
%> (c) LEMS, Brown University
%> Chiang-Heng Chien (chiang-heng_chien@brown.edu)
%> Oct. 30th, 2023

%> Define dataset path
Dataset_Path = "/home/chchien/datasets/";
Dataset_Name = "amsterdam-house-full";
Dataset_File_Struct = dir(fullfile(Dataset_Path, Dataset_Name));
Dataset_File_Struct(1:2, :) = [];

%> Define CEM file source paths
TCG_Contour_Source_Path = "/home/chchien/BrownU/research/SurfacingByLofting/Dataset_TCG_CEM_Files/";
CEM_File_Struct         = dir(fullfile(TCG_Contour_Source_Path, Dataset_Name));
CEM_File_Struct(1:2, :) = [];

%> Get all images from the Dataset_File_Struct
Image_Names = strings(size(CEM_File_Struct, 1), 1);
img_counter = 1;
for i = 1:size(Dataset_File_Struct, 1)
    File_string_Name = Dataset_File_Struct(i).name;
    if contains(File_string_Name, '.jpg')
        Image_Names(img_counter,1) = File_string_Name;
        img_counter = img_counter + 1;
    else
        continue;
    end
end
assert(size(Image_Names, 1) == size(CEM_File_Struct, 1));

%> set visualize parameters and minimal contour length display
params.viz_contour_min_length = 0;
params.max_num_contour_colors = 3000;

%> Create an array of RGB color codes for contour visualization
sz = [params.max_num_contour_colors 3];
contour_RGB_color = unifrnd(0,1,sz);

%> Get third-order edges and countour fragments
for i = 1:size(CEM_File_Struct, 1)
    
    %> Read image
    image_file_dir = fullfile(Dataset_Path, Dataset_Name, Image_Names(i,1));
    img = imread(image_file_dir);
    
    %> Read contours
    File_Name = CEM_File_Struct(i).name;
    cem_file_dir = fullfile(TCG_Contour_Source_Path, Dataset_Name, File_Name);
    [TO_edges, ContourList] = read_cem_file(cem_file_dir);
    
    %> Visualize and also return all contour data
    [all_contour_pos_x, all_contour_pos_y, all_contour_color, ~] = ...
    visualize_contour_groups(img, TO_edges, ContourList, contour_RGB_color, params.viz_contour_min_length);

end
