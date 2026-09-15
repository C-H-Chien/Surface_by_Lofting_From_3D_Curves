function tangent2D = compute_camera_tangents(sampledPts, worldTangents, projMatrix)
%COMPUTE_CAMERA_TANGENTS Project 3D world tangents onto the image plane.
%   sampledPts: Nx3 array of world coordinates
%   worldTangents: Nx3 array of 3D world tangents
%   projMatrix: 3x4 camera matrix [R t]
%
%   tangent2D: Nx2 array of normalized 2D tangent vectors in camera/image space

if nargin < 3 || isempty(sampledPts) || isempty(worldTangents)
    tangent2D = zeros(0, 2);
    return;
end

if size(sampledPts, 2) ~= 3 || size(worldTangents, 2) ~= 3
    error('sampledPts and worldTangents must each be Nx3 arrays.');
end

if size(sampledPts, 1) ~= size(worldTangents, 1)
    error('sampledPts and worldTangents must contain the same number of points.');
end

if size(projMatrix, 1) ~= 3 || size(projMatrix, 2) ~= 4
    error('projMatrix must be a 3x4 camera matrix [R t].');
end

R = projMatrix(:, 1:3);
t = projMatrix(:, 4);
e3 = [0; 0; 1];

nPts = size(sampledPts, 1);
tangent2D = zeros(nPts, 2);

for i = 1:nPts
    Xw = sampledPts(i, :)';
    Tw = worldTangents(i, :)';

    Xc = R * Xw + t;
    Tc = R * Tw;

    if abs(Xc(3)) < 1e-12
        tangent2D(i, :) = NaN(1, 2);
        continue;
    end

    gamma = Xc / Xc(3);
    projectedTangent = Tc - (e3' * Tc) * gamma;
    projectedTangent2D = projectedTangent(1:2);
    normTangent = norm(projectedTangent2D);

    if normTangent > 1e-12
        tangent2D(i, :) = projectedTangent2D' / normTangent;
    else
        tangent2D(i, :) = zeros(1, 2);
    end
end
end
