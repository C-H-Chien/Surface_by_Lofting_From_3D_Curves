function [vertices,faces] = loft_surface(curve1,curve2, reverse_flag, divd)

pt_on_c1 = curve1(ceil(linspace(1, size(curve1, 1), divd)), :);
pt_on_c2 = curve2(ceil(linspace(1, size(curve2, 1), divd)), :);

if reverse_flag
    pt_on_c2 = flip(pt_on_c2, 1);
end

vertices = [];
pt_map = [];
for i = 1:divd
    sp = pt_on_c1(i, :);
    ep = pt_on_c2(i, :);

    dis = norm(sp - ep);
    dir = (ep - sp) ./ dis;

    factor = dis / divd;
    t = [1:divd - 1] * factor;
    sep = repmat(dir', 1, divd - 1);
    sep = sep .* [t; t; t];
    pt = repmat(sp', 1, divd - 1) + sep;
    sz1 = size(vertices, 1);
    vertices = [vertices; sp; pt'; ep];
    sz2 = size(vertices, 1);
    pt_map = [pt_map [sz1+1:sz2]'];
end

faces = [];
[sz1, sz2] = size(pt_map);
for i = 1:sz1 - 1
    for j = 1:sz2 - 1
       v1 = pt_map(i, j);
       v2 = pt_map(i + 1, j);
       v3 = pt_map(i + 1, j + 1);
       v4 = pt_map(i, j + 1);
       faces = [faces; v1 v2 v3];
       faces = [faces; v1 v3 v4];
    end
end

end

