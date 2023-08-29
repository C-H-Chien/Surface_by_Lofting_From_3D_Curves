function curves_after_length_filter = filter_by_length(curves,tau_length, num_of_pts)
    curves_after_length_filter = {};
    for ci = 1:size(curves, 2)
        c = curves{ci};
        if isempty(c), continue; end
        if get_Curve_Length(c) < tau_length
            continue;
        end
        if exist('num_of_pts', 'var') && size(c,1) < num_of_pts
            continue;
        end
        curves_after_length_filter{end + 1} = c;
    end
end

