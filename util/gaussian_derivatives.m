function [outputs, tf] = gaussian_derivatives(order, x, sigma, plot_fig)
    
    % -- plot the Gaussian curves --
%     inputs = -6:6;
%     sigma = 1.0:0.5:3;
%     order = 0;
%     [outputs, tf] = gaussian_derivatives(order, inputs', sigma', 1);
    

    % -- define some constants --
    sqrt_2pi = sqrt(2*pi);
    tf = 1;
    outputs = zeros(size(x,1), size(sigma,1));

    % -- associate the order of Gaussian function accroding to the input --
    switch order
        case 0
            for i = 1:size(x, 1)
                for s = 1:size(sigma,1)
                    outputs(i,s) = (1/(sigma(s,1)*sqrt_2pi)) * exp(-0.5*(x(i,1)^2/sigma(s,1)^2));
                end
            end
        case 1
            for i = 1:size(x, 1)
                for s = 1:size(sigma,1)
                    outputs(i,s) = (-x(i,1)/(sigma(s,1)^3 * sqrt_2pi)) * exp(-0.5*(x(i,1)^2/sigma(s,1)^2));
                end
            end
        case 2
            for i = 1:size(x, 1)
                for s = 1:size(sigma,1)
                    outputs(i,s) = (x(i,1)^2 - sigma(s,1)^2) * (1/(sigma(s,1)^5 * sqrt_2pi)) * exp(-0.5*(x(i,1)^2/sigma(s,1)^2));
                end
            end
        case 3
            for i = 1:size(x, 1)
                for s = 1:size(sigma,1)
                    outputs(i,s) = (3*sigma(s,1)^2 - x(i,1)^2) * (x(i,1)/(sigma(s,1)^7 * sqrt_2pi)) * exp(-0.5*(x(i,1)^2/sigma(s,1)^2));
                end
            end
        otherwise
            disp('input order is invalid\n');
            tf = 0;
    end
    
    if plot_fig && tf
        line_color = ["b*-", "r*-", "g*-", "c*-", "m*-"];
        figure;
        for s = 1:size(sigma,1)
            show_sigma = sprintf('sigma=%.2f',sigma(s,1));
            plot(x(:,1), outputs(:,s), line_color(1,s), 'DisplayName', show_sigma);
            hold on;
        end
        legend;
        set(gcf,'color','w');
    end
end