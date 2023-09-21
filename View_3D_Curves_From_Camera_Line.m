clear;
close all;

%repo_dir = "/home/chchien/BrownU/research/CurveDrawing3D/Zichang_Cowork/Surface_by_Lofting_From_3D_Curves/";

%> All curve points (could be very noisy)
preProcessedCurves = load(fullfile(pwd, 'data', 'preProcessedCurvesPoints.mat')).preProcessedCurves;

%> Step 1) Move the center of the 3D curve drawings to the origin
%> (i) Find maximal and minimal x,y,z coordinates of the 3D curves
world_max_x = -10000;
world_max_y = -10000;
world_max_z = -10000;
world_min_x = 10000;
world_min_y = 10000;
world_min_z = 10000;
for ci = 1:size(preProcessedCurves.points, 2)
    curve = preProcessedCurves.points{ci};
    max_x = max(curve(:,1)); min_x = min(curve(:,1));
    max_y = max(curve(:,2)); min_y = min(curve(:,2));
    max_z = max(curve(:,3)); min_z = min(curve(:,3));    
    if max_x > world_max_x, world_max_x = max_x; end
    if max_y > world_max_y, world_max_y = max_y; end
    if max_z > world_max_z, world_max_z = max_z; end
    if min_x < world_min_x, world_min_x = min_x; end
    if min_y < world_min_y, world_min_y = min_y; end
    if min_z < world_min_z, world_min_z = min_z; end
end
%> (ii) Compute the center position of the 3D curve drawings
center_pos = [world_min_x+(world_max_x-world_min_x)*0.5, ...
              world_min_y+(world_max_y-world_min_y)*0.5, ...
              world_min_z+(world_max_z-world_min_z)*0.5];
%> (iii) Move all 3D curves so that the center is at the origin
curves_centered_at_origin = cell(1, size(preProcessedCurves.points, 2));
for ci = 1:size(preProcessedCurves.points, 2)
    curve = preProcessedCurves.points{ci};
    curve(:,1) = curve(:,1) - center_pos(1,1);
    curve(:,2) = curve(:,2) - center_pos(1,2);
    curve(:,3) = curve(:,3) - center_pos(1,3);
    curves_centered_at_origin{1,ci} = curve;
end

% h1 = figure;
% ax = axes;
% contour_RGB_color = unifrnd(0,1,[size(preProcessedCurves.points, 2) 3]);
% for ci = 1:size(preProcessedCurves.points, 2)
%     figure(h1);
%     curve = curves_centered_at_origin{1,ci};
%     plot3(ax, curve(:,1), curve(:,2), curve(:,3), 'Color', contour_RGB_color(ci,:), 'Marker', '.', 'MarkerSize', 5); 
%     hold(ax, 'on');
%     %text(ax, curve(1,1),curve(1,2), curve(1,3),num2str(ci),'Color',contour_RGB_color(ci,:), 'FontSize', 16);
%     hold(ax, 'on');
% end
% datacursormode;
% xlabel("x");
% ylabel("y");
% zlabel("z");
% axis equal;
% set(gcf,'color','w');
% hold off;

%> Visualize the 3D curve drawing from the perspective of a camera
%> (i) In this example, the camera index 30 is used. Compute the shifted
%      camera center w.r.t. the world coordinate
view_idx_target = 30;
fname1 = sprintf( "/home/chchien/datasets/amsterdam-house-full/%02d.projmatrix", view_idx_target ); %> Change the path of the dataset if necessary
projMatrix = load(fname1);
[K, RT] = Pdecomp(projMatrix);
R_t = RT(1:3,1:3);
T_t = RT(1:3, 4);
C_t = -R_t' * T_t;
C_t_shifted = C_t - center_pos';
%> (ii) Compute the azimuth and elevation angles
[az, el] = normalToAzimuthElevationDEG(C_t_shifted(1), C_t_shifted(2), C_t_shifted(3), 0);
%> (iii) Visualize the result
figure;
for ci = 1:size(preProcessedCurves.points, 2)
    curve = curves_centered_at_origin{1,ci};
    plot3(curve(:,1), curve(:,2), curve(:,3), 'Color', contour_RGB_color(ci,:), 'Marker', '.', 'MarkerSize', 5); 
    hold on;
end
view(az,el);
datacursormode;
xlabel("x");
ylabel("y");
zlabel("z");
axis equal;
set(gcf,'color','w');
hold off;

function [az, el] = normalToAzimuthElevationDEG(x,y,z, applyView)
%> Credit: https://www.mathworks.com/matlabcentral/answers/10734-easy-way-to-set-camera-viewing-axis-normal-to-a-plane
    if nargin < 3
        applyView = 0;
    end
    if length(x)>1
        v         = x;
        if nargin > 1
            applyView = y;
        end
        x=v(1);
        y=v(2);
        z=v(3);
    end
    if x==0 && y==0
        x =eps;
    end
    vNorm = sqrt(x^2+y^2+z^2);
    x=x/vNorm;
    y=y/vNorm;
    z=z/vNorm;
    az = 180/pi*asin(x/sqrt(x^2+y^2));
    el = 180/pi*asin(z);
    if applyView
        thereIsAnOpenFig = ~isempty(findall(0,'Type','Figure'));
        if thereIsAnOpenFig
            axis equal
            view([az,el]);
            %the normal to the plane should now appear as a point
            plot3([0,x],[0,y],[0,z],'linewidth',3)
        end
    end
end
