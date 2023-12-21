function curve_points = sample_bspline(rational, closed, continuity, degree, poles, knots, weights, parameters)
    [curve_points,U] = bspline_deboor(size(knots, 2) - size(poles, 2),knots,poles);
    curve_points = curve_points';
end