clc
clear all


a=1;
b=1;
c=1;
n=0;

[X,Y] = meshgrid(-0.5:0.01:0.5, -0.5:0.01:0.5);
%%%% Hyperbolic_paraboloid
Z=c*((Y./b)^2-(X./a)^2);

for x1=-0.5:0.01:0.5
    for y1=-0.5:0.01:0.5
        z1=c*((y1/b)^2-(x1/a)^2);
        n=n+1;
        x(n,1)=x1;
        y(n,1)=y1;
        z(n,1)=z1;
        %%%% Hyperbolic_paraboloid curvatures: wikipedia
        GC_ex(n,1)=-4*a^6*b^6/(c^2*((a^4*b^4/c^2)+4*b^4*x1^2+4*a^4*y1^2)^2);
        MC_ex(n,1)=-(-a^2+b^2-4*x1^2/a^2+4*y1^2/b^2)/(a^2*b^2*(1+4*x1^2/a^4+4*y1^2/b^4)^1.5);
        
    end
end
      
tri=delaunay(x,y);
[GC,MC]=curvatures(x,y,z,tri);

   

img=figure(1);
clf 
set(img, 'Position', [100 100 600 600]); 
hold on
axis equal
pp= patch('Faces',tri,'Vertices',[x,y,z],'FaceVertexCData',GC,'FaceColor','interp','EdgeColor','none');
caxis([-4 , -0.4])
colormap jet
colorbar
xlabel('x')
ylabel('y')
title('Estimated GC');


img=figure(2);
clf 
set(img, 'Position', [300 100 600 600]); 
hold on
axis equal
pp= patch('Faces',tri,'Vertices',[x,y,z],'FaceVertexCData',MC,'FaceColor','interp','EdgeColor','none');
caxis([-0.36 , 0.36])
colormap jet
colorbar
xlabel('x')
ylabel('y')
title('Estimated MC');


img=figure(3);
clf 
set(img, 'Position', [500 100 600 600]); 
hold on
axis equal
pp= patch('Faces',tri,'Vertices',[x,y,z],'FaceVertexCData',GC_ex,'FaceColor','interp','EdgeColor','none');
caxis([-4 , -0.4])
colormap jet
colorbar
xlabel('x')
ylabel('y')
title('Exact GC');

img=figure(4);
clf 
set(img, 'Position', [700 100 600 600]); 
hold on
axis equal
pp= patch('Faces',tri,'Vertices',[x,y,z],'FaceVertexCData',MC_ex,'FaceColor','interp','EdgeColor','none');
caxis([-0.36 , 0.36])
colormap jet
colorbar
xlabel('x')
ylabel('y')
title('Exact MC');




    