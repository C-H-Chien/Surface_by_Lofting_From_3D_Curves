function [curve_points] = sample_ellipse(focus1, focus2, x_axis, y_axis, x_radius, y_radius, parameters)
%SAMPLE_ELLIPSE Summary of this function goes here
%   Detailed explanation goes here
    location = (focus1 + focus2) ./ 2;
    t = repmat(parameters, 3, 1);
    pt = repmat(location', 1, size(parameters, 2)) + x_radius .* cos(t) .* x_axis' + y_radius .* sin(t) .* y_axis';
    % pt = x_radius .* cos(t) .* x_axis' + y_radius .* sin(t) .* y_axis';

    %> build sequence
    curve_points = pt(:, 1);
    pt(:, 1) = [];
    while size(pt, 2) > 0
        last_pt = curve_points(:, end);
        min_distance = -1;
        closest_idx = -1;
        for i = 1:size(pt, 2)
            curr_pt = pt(:, i);
            dis = sqrt(sum(abs(curr_pt - last_pt) .^ 2, 'all'));
            if i == 1 || dis < min_distance
                min_distance = dis;
                closest_idx = i;
            end
        end
        curve_points(:, end+1) = pt(:, closest_idx);
        pt(:, closest_idx) = [];
    end
    assert(size(curve_points, 2) == size(parameters, 2));
    curve_points = curve_points';
end

