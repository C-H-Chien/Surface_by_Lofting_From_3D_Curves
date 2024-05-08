
%> Third-Order Edge Detector Credit:
%> Paper: Kimia, Benjamin B., Xiaoyan Li, Yuliang Guo, and Amir Tamrakar. 
%         "Differential geometry in edge detection: accurate estimation of 
%         position, orientation and curvature." IEEE transactions on 
%         pattern analysis and machine intelligence 41, no. 7 (2018): 
%         1573-1586.
%> Implementations: (1) https://github.com/yuliangguo/Differential_Geometry_in_Edge_Detection
%                   (2) https://github.com/C-H-Chien/Third-Order-Edge-Detector

% mfiledir = fileparts(mfilename('fullpath'));
Dataset_Path = '/home/chchien/datasets/ABC_NEF/00002211/train_img/';
postfix = '.png';
All_Images = dir(strcat(Dataset_Path, '*', postfix));

%> Settings for the Third-Order Edge Detector
thresh = 1;
sigma = 1;
n = 1;

for i = 1:size(All_Images, 1)
    src_Data_Path = strcat(Dataset_Path, All_Images(i).name);
    img_ = imread(src_Data_Path);
    img_ = double(rgb2gray(img_));
    [TO_edges, ~, ~, ~] = third_order_edge_detector(img_, sigma, n, thresh, 1);
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % outputs of *third_order_edge_detector*
    % TO_edges = [Subpixel_X Subpixel_Y Orientation Confidence]
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    TO_Edges_Name = extractBefore(All_Images(i).name, postfix);

    save_edg([Dataset_Path, TO_Edges_Name, '.edg'], TO_edges, [size(img_, 1), size(img_, 2)]);
    % save(['/home/chchien/TO_Edges_Amsterdam_House/', TO_Edges_Name, '.mat'], 'TO_edges');
    
    %> Monitor the progress
    fprintf(". ");
end
fprintf("\n");

%% 
%> An Example of super-imposing third-order edges on an image
figure;
src_Data_Path = strcat(Dataset_Path, All_Images(1).name);   %> 01.jpg
img_ = imread(src_Data_Path);
img_ = double(rgb2gray(img_));
[TO_edges, ~, ~, ~] = third_order_edge_detector(img_, sigma, n, thresh, 1);
imshow(uint8(img_)); hold on;
plot(TO_edges(:,1), TO_edges(:,2), 'c.');
