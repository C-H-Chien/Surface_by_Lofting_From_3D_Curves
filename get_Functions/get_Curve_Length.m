function len = get_Curve_Length(curve)
%CURVE_LENGTH Summary of this function goes here
%   Detailed explanation goes here
    len = 0;
    for i = 2:size(curve, 1)
        diff_x = curve(i-1, 1) - curve(i, 1);
        diff_y = curve(i-1, 2) - curve(i, 2);
        diff_z = curve(i-1, 3) - curve(i, 3);
        len = len + sqrt(diff_x * diff_x + diff_y * diff_y + diff_z * diff_z);
    end
end

