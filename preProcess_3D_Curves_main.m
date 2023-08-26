clear;
close all;
rng(0);

%> All curve points (could be very noisy)
Curves = load('./data/curve_graph_amsterdam_house_only.mat').houseOnly;

%> Hyper-parameters
PARAMS.SAVE_CURVES_AFTER_LENGTH_CONSTRAINT = 0;

PARAMS.SMOOTHING                           = 1;
PARAMS.SMOOTHING_ACROSS_NUM_OF_DATA        = 500;
PARAMS.TAU_LENGTH                          = 0.6;
PARAMS.TAU_NUM_OF_PTS                      = 600;
PARAMS.GAUSSIAN_DERIVATIVE_SIGMA           = 10;    %> Used for curvature computation
PARAMS.GAUSSIAN_DERIVATIVE_DATA_RANGE      = 20;    %> Used for curvature computation

%> For debugging purpose
PARAMS.DEBUG                               = 1;
PARAMS.DEBUG_COLORMAP_CURVE_INDEX          = 9; %> 26
PARAMS.PLOT_3D_TANGENTS                    = 0;

%> Filter by (i) minimal length constraint, 
%> and (ii) minimal number of curve points constraint
curves_after_length_filter = {};
for ci = 1:size(Curves, 1)
    curve = Curves{ci, 1};
    if isempty(curve), continue; end
    if get_Curve_Length(curve) < PARAMS.TAU_LENGTH
        continue;
    end
    if size(curve,1) < PARAMS.TAU_NUM_OF_PTS
        continue;
    end
    curves_after_length_filter = [curves_after_length_filter; curve];
end

% if ~exist("./tmp", 'dir')
%    mkdir("./tmp")
% end
if PARAMS.SAVE_CURVES_AFTER_LENGTH_CONSTRAINT == 1
    save("./data/curves_after_length_filter", "curves_after_length_filter");
end

to_visualize = curves_after_length_filter;

sz = [size(to_visualize, 1) 3];
contour_RGB_color = unifrnd(0,1,sz);
smoothed_curves = cell(size(to_visualize, 1), 1);
Unit_Tangents3D = cell(size(to_visualize, 1), 1);
Curvatures = cell(size(to_visualize, 1), 1);
h1 = figure(1);
ax = axes;
for ci = 1:size(to_visualize, 1)
    figure(h1);
    
    if PARAMS.SMOOTHING == 1
        
        %> Smooth out curves and display it
        curve = to_visualize{ci, 1};
        sC = smoothdata(curve, "gaussian", PARAMS.SMOOTHING_ACROSS_NUM_OF_DATA);
        smoothed_curves{ci} = sC;
        plot3(ax, sC(:,1), sC(:,2), sC(:,3), 'Color', contour_RGB_color(ci,:), 'Marker', '.', 'MarkerSize', 5); 
        hold(ax, 'on');
        text(ax, sC(1,1),sC(1,2), sC(1,3),num2str(ci),'Color',contour_RGB_color(ci,:), 'FontSize', 16);
        hold(ax, 'on');
        
        %> Compute the unit 3D tangent vectors and the curvatures
        [T, k] = get_UnitTangents_Curvatures(sC(:,1), sC(:,2), sC(:,3), PARAMS);
        Unit_Tangents3D{ci, 1} = T;
        Curvatures{ci, 1} = k;
        
        %> DEBUG: Show the colormap of curvatures of a curve (specified by the PARAMS.DEBUG_COLORMAP_CURVE_INDEX)
        if PARAMS.DEBUG == 1
            if ci == PARAMS.DEBUG_COLORMAP_CURVE_INDEX
                h2 = figure(2);
                h = scatter3(sC(:,1), sC(:,2), sC(:,3), 3, k);
                h.MarkerFaceColor = 'flat';
                colormap(jet);
                colorbar;
                axis equal;
                set(gca, 'xlim', [min(sC(:,1))-0.2, max(sC(:,1))+0.2], ...
                         'ylim', [min(sC(:,2))-0.2, max(sC(:,2))+0.2], ...
                         'zlim', [min(sC(:,3))-0.2, max(sC(:,3))+0.2]);
                xlabel(gca, "x"); ylabel(gca, "y"); zlabel(gca, "z");
                set(gcf,'color','w');
                fprintf("...");
            end
        end
        
        %> Plot unit tangent vectors attached to the curve points.
%         if PARAMS.PLOT_3D_TANGENTS == 1
%             viz_ci = 10:10:size(curve, 1);
%             quiver3(sC(viz_ci,1), sC(viz_ci,2), sC(viz_ci,3), ...
%                     T(viz_ci,1), T(viz_ci,2), T(viz_ci,3), 'color', 'g', 'AutoScaleFactor', 0.1, 'LineWidth', 2);
%         end
    else
        %> Show curves without smoothing
        curve = to_visualize{ci, 1};
        plot3(curve(:,1), curve(:,2), curve(:,3), 'Color', contour_RGB_color(ci,:), 'Marker', '.', 'MarkerSize', 5); 
        hold on;
        text(curve(1,1),curve(1,2), curve(1,3),num2str(ci),'Color',contour_RGB_color(ci,:), 'FontSize', 16);
        hold on;
    end
end

datacursormode;
xlabel("x");
ylabel("y");
zlabel("z");
axis equal;
set(gcf,'color','w');
hold off;
