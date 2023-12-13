clear;
close all;

addpath(fullfile(pwd, 'util'));
rng(0);

%> All curve points (could be very noisy)
input_curves = load(fullfile(pwd, 'data', 'curve_graph_amsterdam.mat')).complete_curve_graph';

%> Hyper-parameters
PARAMS.SAVE_CURVES_AFTER_LENGTH_CONSTRAINT = 0;

PARAMS.SMOOTHING                           = 1;
PARAMS.SMOOTHING_ACROSS_NUM_OF_DATA        = 500;
PARAMS.TAU_LENGTH                          = 0.15;
PARAMS.TAU_NUM_OF_PTS                      = 500;
PARAMS.GAUSSIAN_DERIVATIVE_SIGMA           = 10;    %> Used for curvature computation
PARAMS.GAUSSIAN_DERIVATIVE_DATA_RANGE      = 20;    %> Used for curvature computation
PARAMS.BREAK                               = 1;
PARAMS.MIN_BREAK_CURVATURE                 = 2.5e-3;
%> For debugging purpose
PARAMS.PLOT                                = 1;
PARAMS.DEBUG                               = 1;
PARAMS.DEBUG_COLORMAP_CURVE_INDEX          = 24; %> 26
PARAMS.PLOT_3D_TANGENTS                    = 0;

%> Smooth input curves
if PARAMS.SMOOTHING == 1
    smoothed_curves = cell(size(input_curves, 1), 2);
    for ci = 1:size(input_curves, 2)
        c = input_curves{ci};
        smoothed_curves{ci} = smoothdata(c, "gaussian", PARAMS.SMOOTHING_ACROSS_NUM_OF_DATA);
    end
end

%> Filter by (i) minimal length constraint, 
%> and (ii) minimal number of curve points constraint
if PARAMS.SMOOTHING == 1
    curves_after_length_filter = filter_by_length(smoothed_curves, PARAMS.TAU_LENGTH, PARAMS.TAU_NUM_OF_PTS);
else
    curves_after_length_filter = filter_by_length(input_curves, PARAMS.TAU_LENGTH, PARAMS.TAU_NUM_OF_PTS);
end

tangents = cell(1, size(curves_after_length_filter, 2));
curvatures = cell(1, size(curves_after_length_filter, 2));
for ci = 1:size(curves_after_length_filter, 2)
    curve = curves_after_length_filter{ci};
    %> Compute the unit 3D tangent vectors and the curvatures
    [T, k] = get_UnitTangents_Curvatures(curve(:,1), curve(:,2), curve(:,3), PARAMS);
    tangents{ci} = T;
    curvatures{ci} = k;
end

if PARAMS.BREAK == 1
    breakPoints = cell(1, size(curves_after_length_filter, 2));
    for ci = 1:size(curves_after_length_filter, 2)
        curve = curves_after_length_filter{ci};
        TF = islocalmax(curvatures{ci}, 'MinSeparation',PARAMS.TAU_NUM_OF_PTS,...
            'MinProminence',max(min(maxk(curvatures{ci}, floor(0.1 * size(curvatures{ci}, 1)))), PARAMS.MIN_BREAK_CURVATURE));
        breakPoints{ci} = TF;
    end
end

if PARAMS.BREAK == 1
     preProcessedCurves.points = {};
     preProcessedCurves.curvatures = {};
     preProcessedCurves.tangents = {};
     for ci = 1:size(curves_after_length_filter, 2)
        TF = breakPoints{ci};
        curve = curves_after_length_filter{ci};
        bp = find(TF ~= 0);
        if isempty(bp) || bp(end) ~= size(curve, 1)
            bp = [bp; size(curve, 1)];
        end
        p = 1;
        for bpi = 1:size(bp, 1)
            c = curve(p:bp(bpi), :);
            %> discard curve if it is too short
            if ~isempty(filter_by_length({c}, PARAMS.TAU_LENGTH, PARAMS.TAU_NUM_OF_PTS))
                preProcessedCurves.points{end + 1} = c;
                preProcessedCurves.curvatures{end + 1} = curvatures{ci}(p:bp(bpi), :);
                preProcessedCurves.tangents{end + 1} = tangents{ci}(p:bp(bpi), :);
                assert(size(preProcessedCurves.points{end}, 1) == size(preProcessedCurves.curvatures{end}, 1))
                assert(size(preProcessedCurves.curvatures{end}, 1) == size(preProcessedCurves.tangents{end}, 1))
            end
            p = bp(bpi) + 1;
        end
     end

else
    preProcessedCurves.points = curves_after_length_filter;
    preProcessedCurves.curvatures = curvatures;
    preProcessedCurves.tangents = tangents;
end

%> Save result
if ~exist(fullfile(pwd, "tmp"), 'dir')
    mkdir(fullfile(pwd, "tmp"))
end
if PARAMS.SAVE_CURVES_AFTER_LENGTH_CONSTRAINT == 1
    save(fullfile(pwd, 'tmp', 'curves_after_length_filter'), "curves_after_length_filter");
end
save(fullfile(pwd, 'tmp', 'preProcessedCurves'), "preProcessedCurves");

%> DEBUG: Show the colormap of curvatures of a curve (specified by the PARAMS.DEBUG_COLORMAP_CURVE_INDEX)
if PARAMS.DEBUG == 1
    for ci = 1:size(curves_after_length_filter, 2)
        curve = curves_after_length_filter{ci};
        if ci == PARAMS.DEBUG_COLORMAP_CURVE_INDEX
            figure;
            h = scatter3(curve(:,1), curve(:,2), curve(:,3), 3, curvatures{ci});
            hold on;
            if PARAMS.BREAK == 1
                bp = curve(breakPoints{ci} ~= 0, :);
                scatter3(bp(:, 1), bp(:, 2), bp(:, 3), 100, "red", "filled");
            end
            h.MarkerFaceColor = 'flat';
            colormap(jet);
            colorbar;
            axis equal;
            set(gca, 'xlim', [min(curve(:,1))-0.2, max(curve(:,1))+0.2], ...
                     'ylim', [min(curve(:,2))-0.2, max(curve(:,2))+0.2], ...
                     'zlim', [min(curve(:,3))-0.2, max(curve(:,3))+0.2]);
            xlabel(gca, "x"); ylabel(gca, "y"); zlabel(gca, "z");
            set(gcf,'color','w');
            figure;
            plot(curvatures{ci});
            hold on;
            scatter(find(breakPoints{ci} == 1), curvatures{ci}(breakPoints{ci} == 1), 100, 'red', 'filled');
            hold off;
        end
    end
end

%> PLOT: Plot the result
if PARAMS.PLOT == 1
    h1 = figure;
    ax = axes;
    contour_RGB_color = unifrnd(0,1,[size(curves_after_length_filter, 2) 3]);
    for ci = 1:size(curves_after_length_filter, 2)
        figure(h1);
        curve = curves_after_length_filter{ci};
        plot3(ax, curve(:,1), curve(:,2), curve(:,3), 'Color', contour_RGB_color(ci,:), 'Marker', '.', 'MarkerSize', 5); 
        hold(ax, 'on');
        text(ax, curve(1,1),curve(1,2), curve(1,3),num2str(ci),'Color',contour_RGB_color(ci,:), 'FontSize', 16);
        hold(ax, 'on');
        if PARAMS.BREAK == 1
            bp = curve(breakPoints{ci} ~= 0, :);
            scatter3(bp(:, 1), bp(:, 2), bp(:, 3), 100, "red", "filled");
            hold(ax, 'on');
        end
        
    end
    datacursormode;
    xlabel("x");
    ylabel("y");
    zlabel("z");
    axis equal;
    set(gcf,'color','w');
    hold off;
    
    %> Plot breaked curves after filtering out short ones
    if PARAMS.BREAK == 1
        h1 = figure;
        ax = axes;
        contour_RGB_color = unifrnd(0,1,[size(preProcessedCurves.points, 2) 3]);
        for ci = 1:size(preProcessedCurves.points, 2)
            figure(h1);
            curve = preProcessedCurves.points{ci};
            plot3(ax, curve(:,1), curve(:,2), curve(:,3), 'Color', contour_RGB_color(ci,:), 'Marker', '.', 'MarkerSize', 5); 
            hold(ax, 'on');
            text(ax, curve(1,1),curve(1,2), curve(1,3),num2str(ci),'Color',contour_RGB_color(ci,:), 'FontSize', 16);
            hold(ax, 'on');
            
        end
        datacursormode;
        xlabel("x");
        ylabel("y");
        zlabel("z");
        axis equal;
        set(gcf,'color','w');
        hold off;
    end

    %> Plot unit tangent vectors attached to the curve points.
    if PARAMS.PLOT_3D_TANGENTS == 1
        h2 = figure;
        ax = axes;
        for ci = 1:size(curves_after_length_filter, 2)
            figure(h2);
            curve = curves_after_length_filter{ci};
            viz_ci = 10:10:size(curve, 1);
            quiver3(curve(viz_ci,1), curve(viz_ci,2), curve(viz_ci,3), ...
                    tangents{ci}(viz_ci,1), tangents{ci}(viz_ci,2), tangents{ci}(viz_ci,3), 'color', 'g', 'AutoScaleFactor', 0.1, 'LineWidth', 2);
            hold(ax, 'on');
        end
    end
end




