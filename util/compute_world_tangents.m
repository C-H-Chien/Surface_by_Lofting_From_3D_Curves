function tangents = compute_world_tangents(sampledPts)
%COMPUTE_WORLD_TANGENTS Compute finite-difference tangents for sampled 3D points.
% Each tangent is computed as (x_plus - x_minus) / ||x_plus - x_minus||
% using the neighboring points along the sampled boundary sequence.
if nargin < 1 || isempty(sampledPts)
    tangents = zeros(0, 3);
    return;
end
sampledPts = double(sampledPts);
nPts = size(sampledPts, 1);
tangents = zeros(nPts, 3);
if nPts == 1
    return;
end
if nPts == 2
    delta = sampledPts(2, :) - sampledPts(1, :);
    normDelta = sqrt(sum(delta.^2, 2));
    if normDelta > 1e-12
        tangents(1, :) = delta / normDelta;
        tangents(2, :) = delta / normDelta;
    end
    return;
end
for i = 1:nPts
    prevIdx = i - 1;
    nextIdx = i + 1;
    if prevIdx < 1
        prevIdx = nPts;
    end
    if nextIdx > nPts
        nextIdx = 1;
    end
    delta = sampledPts(nextIdx, :) - sampledPts(prevIdx, :);
    normDelta = sqrt(sum(delta.^2, 2));
    if normDelta > 1e-12
        tangents(i, :) = delta / normDelta;
    end
end
end
