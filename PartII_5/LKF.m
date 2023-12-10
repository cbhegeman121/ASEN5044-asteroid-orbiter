clc
clear
close all
format longg

addpath(genpath(fileparts(pwd)))

data = load('orbitdetermination-finalproj_data_2023_11_14.mat');

global mu fo wA u0 umin umax sigW sigU
mu = 4.892E-9;              % gravity parameter of asteroid
fo = 2089.7959;             % Pixels
wA = 2*pi/(4.296057*3600);  % rad/s; asteroid rotation rate
u0 = [512 512]';            % center of optical plane
umin = [0 0]';              % Pixels
umax = [1024 1024]';        % Pixels
sigW = 1E-9;
sigU = 0.25;

delTint = 60;               % s
delTobs = 600;              % s
tEnd = 72*60*60;            % 72h -> s



r0 = [0 -1 0]';
rdot0 = [0 0 sqrt(mu/norm(r0))]';
state0 = [r0; rdot0];
asrp = f.solarRadPress();
asrp = asrp(4:6);

NL_state = zeros(6,length(1:delTint:tEnd)+2);
NL_state(:,1) = state0;

wTilde = noiseMaker(zeros(3,1),(sigW^2)*eye(3),length(NL_state))';
gammaW = [zeros(3); eye(3)];
W = sigW^2;
Q = DTsys.noiseMat(W,delTobs);

linear_state = zeros(6,length(1:delTobs:tEnd)+1);
linear_state(:,1) = state0;

meas = nan(2,length(1:delTobs:tEnd)+1);
y_table = [];
NL_y = nan(2,length(1:delTobs:tEnd)+1);

vTilde = noiseMaker(zeros(2,1),(sigU^2)*eye(2),length(NL_y));
V = (sigU^2)*eye(2);
R = V/delTobs;

j = 1;


for i=1:(tEnd/delTint)+1
    NL_state(:,i+1) = rk4_state(NL_state(:,i),delTint); % + gammaW*wTilde(:,i);

    time = (i-1)*delTint;

    if(~mod(time,delTobs))
        r = NL_state(1:3,i);

        Rcn = data.R_CtoN(:,:,j);
        ic = Rcn(:,1);
        jc = Rcn(:,2);
        kc = Rcn(:,3);

        theta = wA*time;
        Rna = [cos(theta) -sin(theta) 0;
               sin(theta) cos(theta) 0;
               0 0 1];

        for l=1:50       
            lpos = data.pos_lmks_A(:,l);
            lrot = Rna*lpos;

            u_y = ((fo*(lrot-r)'*ic)/((lrot-r)'*kc)) + u0(1);
            v_y = ((fo*(lrot-r)'*jc)/((lrot-r)'*kc)) + u0(2);

            if(isVisible([u_y; v_y],lrot,r,kc))
                y_table(end+1,:) = [time l u_y v_y];
            end
        end

        j = j+1;
    end

end



linear_meas = [];
P0 = [10*eye(3) zeros(3);
      zeros(3) 0.0005*eye(3)];
xP(:,1) = state0;
P_P(:,:,1) = P0;
xM = [];
P_M = [];


for j=1:(tEnd/delTobs)+1

    time = (j-1)*delTobs;

    NLind = ((j-1)*10)+1;

    x = NL_state(1,NLind);
    y = NL_state(2,NLind);
    z = NL_state(3,NLind);
    NL_r = norm(NL_state(1:3,NLind));

    [A,B] = CTsys.dynMat(x,y,z,NL_r);
    [F,G] = DTsys.dynMat(A,B,delTobs);      

    linear_state(:,j+1) = F*linear_state(:,j)+G*asrp;
  
    r = linear_state(1:3,j);

    Rcn = data.R_CtoN(:,:,j);
    ic = Rcn(:,1);
    jc = Rcn(:,2);
    kc = Rcn(:,3);

    theta = wA*time;
    Rna = [cos(theta) -sin(theta) 0;
           sin(theta) cos(theta) 0;
           0 0 1];

    
    [xM(:,end+1),P_M(:,:,end+1)] = kalmanFilter.timeUpd(xP(:,end),asrp,P_P(:,:,end),F,G,Q);
    xP_temp = xM(:,end);
    P_P_temp = P_M(:,:,end);

    lmks = y_table(find(y_table(:,1)==time),2:4); 

    for l=1:50
        lmk = lmks(find(lmks(:,1)==l),2:3);

        if(~isempty(lmk))
            lpos = data.pos_lmks_A(:,l);
            lrot = Rna*lpos;
            [H,M] = CTsys.measMat(NL_r,lrot,ic,jc,kc);
            
            linear_meas(end+1,:) = [time l (H*linear_state(:,j))'];
            [xP_temp,P_P_temp] = kalmanFilter.measUpd(length(A),xP_temp,lmk',P_P_temp,H,R);
        end

    end

    xP(:,end+1) = xP_temp;
    P_P(:,:,end+1) = P_P_temp;
end

% Psig(1,:) = P_P(1,1,:);


% plot(1:(tEnd/delTobs)+2,xP(1,:))
% hold on
% plot(1:(tEnd/delTobs)+2,linear_state(1,:))
% plot(1:(tEnd/delTobs)+2,2*sqrt(Psig(1,:))+xP(1,:),'black --')
% plot(1:(tEnd/delTobs)+2,-2*sqrt(Psig(1,:))+xP(1,:),'black --')

rows = 1:length(y_table);

plot(y_table(rows,3),y_table(rows,4),'blue x')
hold on
plot(linear_meas(rows,3),linear_meas(rows,4),'red o')
xlim([umin(1) umax(1)])
ylim([umin(1) umax(1)])
