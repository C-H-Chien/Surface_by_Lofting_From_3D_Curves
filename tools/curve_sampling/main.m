clear;
close all;

import yaml.*
mfiledir = fileparts(mfilename('fullpath'));
addpath(fullfile(mfiledir, "bspline/"));

%> Use abc_0000_feat_v00/00000325 as example
media_storage = "/media/chchien/843557f5-9293-49aa-8fb8-c1fc6c72f7ea/";
dataset_name = "ABC-NEF/";
dataset_path = "/home/chchien/datasets/";
object_tag = "00000325";
save_curve_mat_file = 1;

ymlPath = fullfile(media_storage, dataset_path, dataset_name, object_tag, strcat(object_tag, ".yml"));
data = yaml.loadFile(ymlPath);
curves = data.curves;

curve_points = {};
for i = 1:size(curves, 2)
    c = curves{i};
    if strcmp(c.type, "Line")
        curve_points{end + 1} = sample_line(cell2mat(c.location), cell2mat(c.direction), cell2mat(c.vert_parameters));
    elseif strcmp(c.type, "Circle")
        curve_points{end + 1} = sample_circle(cell2mat(c.location), c.radius, cell2mat(c.x_axis), cell2mat(c.y_axis), cell2mat(c.vert_parameters));
    elseif strcmp(c.type, "Ellipse")
        % disp("Ellipse is not well supported");
        % return;
        curve_points{end + 1} = sample_ellipse(cell2mat(c.focus1), cell2mat(c.focus2), cell2mat(c.x_axis), cell2mat(c.y_axis), c.maj_radius, c.min_radius, cell2mat(c.vert_parameters));
    elseif strcmp(c.type, "BSpline")
        p = [];
        for j = 1:size(c.poles, 2)
            p(:, end+1) = cell2mat(c.poles{j})';
        end
        try
            curve_points{end + 1} = sample_bspline(c.rational, c.closed, c.continuity, c.degree, p, cell2mat(c.knots), cell2mat(c.weights), cell2mat(c.vert_parameters));
        catch
            disp("Failed to sample a b-spline");
        end
    end
end

%>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
%> Scale down the ground-truth curves to fit it within a 1x1x1 bounding box
%> This is only applied when using the ABC-NEF dataset
%>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
if strcmp(dataset_name, "ABC-NEF/")
    scale_min = [inf inf inf];
    scale_max = [-inf -inf -inf];
    
    for i = 1:length(curve_points)
        c = curve_points{i};
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
    shift_curves = curve_points;
    for i = 1:length(curve_points)
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
    end
else
    final_curves = curve_points;
end

%>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

for i = 1:size(final_curves, 2)
    c = final_curves{i};
    plot3(c(:, 1), c(:, 2), c(:, 3), 'Color', 'g', 'LineWidth', 2);
    hold on
end
hold off;
xlabel('x');
ylabel('y');
zlabel('z');
axis equal;
% axis off;
set(gcf,'color','w');

if save_curve_mat_file == 1
    curve_points = final_curves;
    save(fullfile(media_storage, dataset_path, dataset_name, object_tag, "curves.mat"), "curve_points");
end
