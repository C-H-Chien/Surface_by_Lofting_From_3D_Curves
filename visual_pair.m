clear;
input_curves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;
pairs = load(fullfile(pwd, 'data', 'manual_pick.mat')).manual_pick;
figure;
ax = axes;


for i = 1:size(pairs, 1)
    p1 = pairs(i, 1);
    p2 = pairs(i, 2);
    disp(int2str(p1) + " " + int2str(p2));
    for ci = 1:size(input_curves, 2)
        curve = input_curves{ci};
        if ci == p1 || ci == p2
            plot3(ax, curve(:,1), curve(:,2), curve(:,3), 'Color', 'red', 'Marker', '.', 'MarkerSize', 5); 
            hold(ax, 'on');
            text(ax, curve(1,1),curve(1,2), curve(1,3),num2str(ci),'Color','red', 'FontSize', 16);
            hold(ax, 'on');
        else
            plot3(ax, curve(:,1), curve(:,2), curve(:,3), 'Color', 'black', 'Marker', '.', 'MarkerSize', 5); 
            hold(ax, 'on');
            text(ax, curve(1,1),curve(1,2), curve(1,3),num2str(ci),'Color','black', 'FontSize', 16);
            hold(ax, 'on');
        end
    end
    datacursormode;
    xlabel("x");
    ylabel("y");
    zlabel("z");
    axis equal;
    set(gcf,'color','w');
    hold off
end