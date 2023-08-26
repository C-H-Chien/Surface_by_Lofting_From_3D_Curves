function [T, k] = get_UnitTangents_Curvatures(x, y, z, PARAMS)

%> Example
%  clear,clc
%  
%  t = 2*pi*linspace(-1/2,1/2,100).';
%  
%  x = cos(t); 
%  y = sin(t); 
%  z = t;
%  T = getUnitTangents(x,y,z);

x=x(:); y=y(:);

sz=size(x);
if nargin==2, z=zeros(sz); end

%> make column vectors
z = z(:); 

%> Calculate derrivatives of the curve
X = csaps(1:sz(1),x,1);
Y = csaps(1:sz(1),y,1);
Z = csaps(1:sz(1),z,1);
mx = fnval(fnder(X,1),1:sz(1)).';
my = fnval(fnder(Y,1),1:sz(1)).';
mz = fnval(fnder(Z,1),1:sz(1)).';

ind = find(sqrt(sum([mx my mz].*[mx my mz],2))>0);
data = [mx(ind) my(ind) mz(ind)]; % discard bad points

%> Normalization
T = bsxfun(@rdivide, data, sqrt(sum(data.*data,2)));
T = interp1(ind, T, 1:sz(1), '*linear', 'extrap');
T = bsxfun(@rdivide, T ,sqrt(sum(T.*T,2)));

%> Get first-order Gaussian derivative 
sigma = PARAMS.GAUSSIAN_DERIVATIVE_SIGMA;
range_sz = PARAMS.GAUSSIAN_DERIVATIVE_DATA_RANGE;
data_range = -range_sz:1:range_sz;
ker_size = data_range';
[Gfp, ~] = gaussian_derivatives(1, ker_size, sigma, 0);
% Gfp = gradient(G1);

padded_T = [[T(1,1).*ones(range_sz,1), T(1,2).*ones(range_sz,1), T(1,3).*ones(range_sz,1)]; T];
padded_T = [padded_T; [T(end,1).*ones(range_sz,1), T(end,2).*ones(range_sz,1), T(end,3).*ones(range_sz,1)]];

dTx = conv(padded_T(:,1), Gfp, 'same');
dTy = conv(padded_T(:,2), Gfp, 'same');
dTz = conv(padded_T(:,3), Gfp, 'same');
dT = [dTx(range_sz+1:end-range_sz), dTy(range_sz+1:end-range_sz), dTz(range_sz+1:end-range_sz)];

k = zeros(size(dT,1), 1);
for i = 1:size(dT,1)
    k(i,1) = norm(dT(i,:));
end

