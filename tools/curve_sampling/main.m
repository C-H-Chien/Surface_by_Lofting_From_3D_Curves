clear;
close all;

import yaml.*
mfiledir = fileparts(mfilename('fullpath'));
addpath(fullfile(mfiledir, "bspline/"));

%> Use abc_0000_feat_v00/00000325 as example
dataset_path = "/home/chchien/datasets/ABC_NEF/";
object_tag = "00000568";

ymlPath = fullfile(dataset_path, object_tag, strcat(object_tag, ".yml"));
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
        disp("Ellipse is not well supported");
        return;
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

for i = 1:size(curve_points, 2)
    c = curve_points{i};
    plot3(c(:, 1), c(:, 2), c(:, 3));
    hold on
end
hold off;
axis equal;
save(fullfile(dataset_path, object_tag, "curves.mat"), "curve_points");
