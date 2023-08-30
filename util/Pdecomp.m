function [K, varargout]= Pdecomp(P)
%
%  (1) K=Pdecomp(P)
%  (2) [K,E]=Pdecomp(P)
%  (3) [K,R,IminusC]= Pdecomp(P)
%
%out:
%
%  K: intrinsic matrix 3x3
%  E: extrincsic matrix 3x4 such that P=K*E
%  R, IminusC:  3x3 orthogonal matrix R and 3x4 matrix IminusC 
%               such that P=K*R*IminusC where C is the focal spot and
%               IminusC=[eye(3), -C]
              




              M=P(:,1:3,1);
              
              L=[.5,.5,0]*sqrt(sum(M.^2,2));
              Dm=diag([1,1,L]); %preconditioner
              
              
              
               [Km,R]=rqdecomp(Dm*M);
                
                 
               E=Km\(Dm*P);
               IminusC=R\E;
               K=Km; 
                 K(end,:)=K(end,:)/L;
               
               varargout={};

               
               
               
               if nargout==2

                  varargout{1}=E; 
               end

               if nargout==3

                   varargout{1}=R;
                   varargout{2}=IminusC;

               end
               
               
 function [R,Q]=rqdecomp(A)
%RQ decomposition of matrix A
%
%    [R,Q]=rqdecomp(A)

   [Q,R]=qr(fliplr(A.'),0);
   
   Q=fliplr(Q).';
   R=rot90(R,2).';
   
   c=sign(diag(R));
   c(~c)=1;
   C=spardiag(c);
   
   R=R*C;
   Q=C*Q;
   
   
function M=spardiag(V)
%makes a sparse n-by-n diagonal matrix with V on the diagonal where V
%is length n.
%
% M=spardiag(V)

if ~isa(V,'double') || ~islogical(V);
 V=double(V);
end

N=numel(V);

M=spdiags(V(:),0,N,N);