function [curve_points] = sample_circle(location, radius, x_axis, y_axis, parameters)
%SAMPLE_CIRCLE Summary of this function goes here
%   Detailed explanation goes here
    t = repmat(parameters, 3, 1);
    pt = repmat(location', 1, size(parameters, 2)) + radius .* cos(t) .* x_axis' + radius .* sin(t) .* y_axis';
    
    %> build sequence
    curve_points = pt(:, 1);
    pt(:, 1) = [];
    while size(pt, 2) > 0
        last_pt = curve_points(:, end);
        min_distance = inf;
        closest_idx = -1;
        for i = 1:size(pt, 2)
            curr_pt = pt(:, i);
            dis = sqrt(sum(abs(curr_pt - last_pt) .^ 2, 'all'));
            if dis < min_distance
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

