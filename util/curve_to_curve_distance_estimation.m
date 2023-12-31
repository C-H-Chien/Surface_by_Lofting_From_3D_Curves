function res = curve_to_curve_distance_estimation(curve1,curve2, divd)
    pt_on_c1 = curve1(ceil(linspace(1, size(curve1, 1), divd)), :);
    pt_on_c2 = curve2(ceil(linspace(1, size(curve2, 1), divd)), :);
    sz1 = size(pt_on_c1, 1);
    sz2 = size(pt_on_c2, 1);
    dis = zeros(sz1, sz2);
    for i = 1:sz1
        for j = 1:sz2
            diff_x = curve1(i, 1) - curve2(j, 1);
            diff_y = curve1(i, 2) - curve2(j, 2);
            diff_z = curve1(i, 3) - curve2(j, 3);
            dis(i, j) = sqrt(diff_x * diff_x + diff_y * diff_y + diff_z * diff_z);
        end
    end
    min_col = min(dis, [], 1);
    min_row = min(dis, [], 2);
    res =  (sum(min_col, 'all') + sum(min_row, 'all')) / (sz1 + sz2);
end

