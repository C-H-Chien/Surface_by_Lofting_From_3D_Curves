function [curve_points] = sample_line(location,direction, parameters)
%SAMPLE_LINE Summary of this function goes here
%   Detailed explanation goes here
    % t = repmat(linspace(0, 1, divd), 3, 1);
    % curve_points = repmat(location', 1, divd) + direction' .* t;
    t = repmat(parameters, 3, 1);
    curve_points = repmat(location', 1, size(parameters, 2)) + direction' .* t;
    curve_points = curve_points';
end
