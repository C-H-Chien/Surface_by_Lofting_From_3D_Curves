function [all_contour_pos_x, all_contour_pos_y, all_contour_color, color_indx_img_map] = ...
         visualize_contour_groups(img, TO_edges, ContourList, contour_RGB_color, viz_contour_min_length)

%> Code Description: 
%     Given a RGB (or grayu) image, its corresponding third-order edges,
%     contours read from a .cem file through read_Cem_file.m, an array of
%     RGB color codes, and the minimal contour length for visualization,
%     show contour fragments superimporsed on the image and return contour
%     positions and their color codes.
%
%> Inputs: 
%     img:                    Source RGB/gray image.
%     TO_edges:               Third-order edges. Should be given by the 
%                             output of read_cem_file.m file. 
%     ContourList:            A list of contours read from a .cem file
%                             through read_cem_file.m file. 
%     contour_RGB_color:      An Nx3 array of RGB color codes, where N is a
%                             comparatively large number.
%     viz_contour_min_length: Minimal contour length for visualization.
%
%> Outputs:
%     all_contour_pos_x:  All contour positions of x dimension.
%     all_contour_pos_y:  All contour positions of y dimension.
%     all_contour_color:  Indices of color codes for each contour.
%     color_indx_img_map: A map of size same as the input image containing
%                         the indices of contours.
%
%
%> (c) LEMS, Brown University
%> Chiang-Heng Chien (chiang-heng_chien@brown.edu)
%> Aug. 2nd, 2022
     
     
    %> image height and width
    opts.w = size(img,2);
    opts.h = size(img,1);

    %> show image first
    imshow(img);
    hold on;
    
    max_sz_contour = size(ContourList, 2);
    
    %> RGB color index map
    color_indx_img_map = zeros(opts.h, opts.w);
    
    %> record all subpix positions of the contours
    all_contour_pos_x = zeros(size(ContourList,1), max_sz_contour);
    all_contour_pos_y = zeros(size(ContourList,1), max_sz_contour);
    all_contour_color = zeros(size(ContourList,1), 1);
    
    %> make sure that the size of RGB_color list is the same as the number of contours
    if size(ContourList, 1) > size(contour_RGB_color, 1)
        rng('default');
        rng(1);
        num_of_contours = size(ContourList, 1);
        sz = [num_of_contours 3];
        contour_RGB_color = unifrnd(0,1,sz);
    end
    
    %> loop over all contour list
    for i = 1:size(ContourList,1)
        contour_pos = zeros(max_sz_contour, 2);
        contour_length = 0;
        for k = 1:max_sz_contour
            if ContourList(i,k) > 0
                contour_length = contour_length + 1;
            end
        end

        if contour_length <= viz_contour_min_length
            continue;
        end

        for j = 1:max_sz_contour
            if ContourList(i,j) > 0
                px = TO_edges(ContourList(i,j), 1);
                py = TO_edges(ContourList(i,j), 2);
                if round(px) <= 0 || round(py) <= 0 || px > opts.w || py+10>opts.h
                   continue;
                else
                    contour_pos(j,1) = px;
                    contour_pos(j,2) = py;
                    all_contour_pos_x(i, j) = px;
                    all_contour_pos_y(i, j) = py;
                    
                    color_indx_img_map(round(py), round(px)) = i;
                    all_contour_color(i, 1) = i;
                end
            else
                break;
            end
        end

        %plot(contour_pos(:,1), contour_pos(:,2), '.', 'Color', contour_RGB_color(i,:), 'MarkerSize', 7);
        show_indices = find(contour_pos(:,1) > 0);
        show_contours = contour_pos(show_indices, :);
        line(show_contours(:,1), show_contours(:,2), 'color', contour_RGB_color(i,:), 'LineWidth', 2);
        hold on;
    end

    %hold off;
end