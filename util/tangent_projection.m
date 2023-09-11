function [theta, vec] = tangent_projection(curve,tangent, projMatrix)
%TANGENT_PROJECTION Project tangent vector to image plane
%   Detailed explanation goes here

    assert(isequal(size(curve), size(tangent)));

    %> project curve to image plane
    curve_proj = projMatrix * [curve ones(size(curve, 1), 1)]';
    curve_proj = curve_proj(1:2, :) ./ curve_proj(3, :);

    %> project tangent vector end point to image plane
    tangent_endpoint = projMatrix * [curve + tangent ones(size(curve, 1), 1)]';
    tangent_endpoint = tangent_endpoint(1:2, :) ./ tangent_endpoint(3, :);

    %> calculate the tangent vector projection and normalize
    vec = tangent_endpoint - curve_proj;
    vec = vec ./ sqrt(sum(vec .^ 2, 1));
    vec = vec';
    theta = acos(vec(:, 1));
    %> theta in range [-pi, pi], use sin(theta) determin positive or
    % negtive
    theta = theta .* (ones(size(theta)) - 2 * (vec(:, 2) < 0));
end

