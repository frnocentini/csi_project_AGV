
% Uses the Robust Control toolbox
close all
global rp w_rp


s = tf('s');
J = get_linearization();
A = J.A;
B = J.B;
A_i = J.A_i;
B_i = J.B_i;
C = J.C;
D = J.D;
SYS = ss(A,B,C,D);    % funzione di trasferiemnto del sistema nominale
Gnom = minreal(tf(SYS));
[Anom Bnom Cnom Dnom] = ssdata(Gnom);
sys = minreal(ss(Anom,Bnom,Cnom,Dnom));
% autovalori = sigma(T);
% sigma(T)
omega = logspace(-1,6,302);
%
% Weights.
%
rp_tau = w_rp/(rp);
wi = 5*rp_tau*rp*s/(1+rp*s);

%sta sopra da 10^-8
%wi = 1/(1+s*10^8)^3*1/(1+s*10^6)^2*(1+s*10^3)^5*(1+s*10^17)^10*1/(1+s*10^15)^10;


%Funzione peso che sta sopra i valori singolari da 10^-5 in poi 
%muRSinf = 0.1322; muNPinf = 0.0729; muRPinf = 0.2841
%Non funziona con la dk
% wi = 1/(1+s*10^10)^2*1/(1+s*10^6)^2*(1+s*10^3)^4*(1+s*10^17)^10*1/(1+s*10^15)^10;
Gp = C*(s*eye(5)-A_i)^(-1)*B_i; %G incerta
G_inv = inv(sys'*sys)*sys';%pseudoinversa sinistra
sigma(G_inv*(Gp-sys),[10^0.5,10^4]); hold on; sigma(wi,[10^0.5,10^4]);

% freq = [1.40494020600125e-14
% 6.69677303868978e-07
% 0.249740006959577
% 2368.13236993714
% 67387776523264.6];
% 
% response = [849.322493224932
% 504.607046070460
% 10.2981029810296
% -93.7669376693768
% -76.4227642276426];
% system = frd(10.^(response/20),freq');
% wi = fitmagfrd(system,4,0);
% wi = minreal(tf(wi));


Wi = blkdiag(wi,wi);
M = 2; %picco massimo di S che da prassi garantisce buoni margini di guadagno sul sistema
AP = 3; %errore massimo a regime
wBp = 1; %frequenza minima di banda per la performance
%wP = (s/(M)^1/2+wBp)^2/(s+wBp*(AP)^1/2)^2; %wp per maggiore pendenza 
wP = (s/M+wBp)/(s+wBp*AP); %peso sulla performance% Matrici di peso
Wu = tf(1);  %peso sullo sforzo di controllo
wBt = 1;
wT = s/(s+wBt);%peso sul rumore di misura
WT = blkdiag(wT,wT,wT,wT);
%Definizione dei parametri
% M = 2;
% AP = 10^-2;
% wBp = 10^-2;
% wBt = 1;
% wBu = 1;
% % Matrici di peso
% Wu = s/(s+wBu);
% %wP = (s/M+wBp)/(s+wBp*AP);

WP = blkdiag(wP,wP,wP,wP);
WU = blkdiag(Wu,Wu);


%% Generalized plant P with Wi, Wu and Wp
systemnames = 'sys WT WP WU Wi';
inputvar = '[udel{2}; w{4}; u{2}]';
outputvar = '[Wi ; WP ; WU; -w-sys]';
input_to_sys = '[u+udel]';
input_to_WT = '[sys]';
input_to_WP = '[sys+w]';
input_to_WU = '[u]';
input_to_Wi = '[u]';
sysoutname = 'P';
cleanupsysic = 'yes';
sysic;
P = minreal(ss(P));

Delta = ultidyn('Delta',[2 2]);
                          

%% DK-iteration tramite musyn
% Il comando musyn prende la mixed-mu M in ingresso, sapendo che M = lft(delta,N)
% dove qui al posto della N si ha la P
nmeas = 4; nu = 2;  
omega = logspace(-1,6,302);
M=lft(Delta,P);
opts=musynOptions('Display','full','MaxIter',100,'TolPerf',0.001,'FrequencyGrid',omega)
[K_DK,CLPperf,info_mu]=musyn(M,nmeas,nu,opts);

%% DK ITERATION MANUALE 
% funzione di interpolazione scelta di ordine 2
%con la funzione wi di grado 1 funziona bene fino alla quarta iterazione
%poi si perde ma arriva a muRP<1

omega = logspace(-3,3,61);
blk = [1 1; 1 1; 1 1; 1 1; 1 1; 1 1];
nmeas = 4; nu = 2; d0 = 1; 
%delta in questo caso è diag{delta_i, delta_p}
%delta_i è un blocco diagonale 2x2 ed è per questo che ho [1 1; 1 1];
%delta_P invece è una matrice piena (non diagonale)
D_left = append(d0,d0,tf(eye(8)),tf(eye(2)));
D_right = append(d0,d0,tf(eye(2)),tf(eye(4)));
%
% START ITERATION.
%
% STEP 1: Find H-infinity optimal controller
% with given scalings:
%

    [K_DK,Nsc,gamma,info] = hinfsyn(D_left*P*inv(D_right),nmeas,nu,....
                   'method','lmi','Tolgam',1e-3);
    

    Nf = frd(lft(P,K),omega);
%
gamma_prec = gamma+1; 
gamma_corr = gamma;
N_it = 0;
while (N_it<10)
% STEP 2: Compute mu using upper bound:
    %Verifica della robusta stabilità
    [mubnds,Info] = mussv(Nf(1:2,1:2),[1 1;1 1],'c'); 
    bodemag(mubnds(1,1),omega);
    murs = norm(mubnds(1,1),inf,1e-6);
    %Verifica della performance nominale
    [mubnds_pn,Info_np] = mussv(Nf(3:8,3:6),[4 6],'c');
    bodemag(mubnds_pn(1,1),omega);
    munp = norm(mubnds_pn(1,1),inf,1e-6);
    %Verifica della robusta performance
    [mubnds_rp,Info_rp] = mussv(Nf,[1 1;1 1;4 6],'c');
    bodemag(mubnds_rp(1,1),omega);
    murp = norm(mubnds_rp(1,1),inf,1e-6)
%   
% STEP 3: Fit resulting D-scales:
%
    [dsysl,dsysr] = mussvunwrap(Info_rp);
    dsysl = dsysl/dsysl(3,3);
    func_order_4 = fitfrd(genphase(dsysl(1,1)),2); 
    %viene generata la fase interpolando con una funzione del 4° ordine
    %func_order_4=func_order_4.C*(inv(s*eye(4)-func_order_4.A))*func_order_4.B+func_order_4.D; 
    % poiché viene restituita in forma di stato viene trasfromata in 
    % funzione di trasferimento prima di metterla in Dk
    d0 = tf(minreal(func_order_4));
    
%     func_order_4_p = fitfrd(genphase(dsysl_p(1,1)),4);
%     func_order_4_p=func_order_4_p.C*(inv(s*eye(4)-func_order_4_p.A))*func_order_4_p.B+func_order_4_p.D; 
%     D_right=func_order_4_p;
    D_left = append(d0,d0,tf(eye(10)));
    D_right = append(d0,d0,tf(eye(6)));
    
     [K_DK,Nsc,gamma,info] = hinfsyn(D_left*P*inv(D_right),nmeas,nu,....
                   'method','lmi','Tolgam',1e-3);

    Nf = frd(lft(P,K),omega);

%     gamma_prec = gamma_corr;
%     gamma_corr = gamma;
    N_it = N_it+1;
  
end


%% sezione da eseguire per SIMULINK una volta sintetizzato il controllore
[A_DK B_DK C_DK D_DK] = ssdata(K);
%% RS con robuststab

looptranfer = loopsens(Gp, K);
Ti = looptranfer.Ti;
Tif = ufrd(Ti, omega);
opt = robopt('Display','on');
%in particolare stabmarg mi indica gli upper e lower bound, l'inverso del
%lower bound deve essere uguale al muRSinf ottenuto con il comando mussv
%destabunc mi indica esattamente l'incertezza massima tollerabile dal
%sistema oltre la quale non è robustamente stabile
[stabmarg, destabunc, report] = robuststab(Tif,opt) 
%incertezza massime che mi porterebbero all'instabilità

%RP analysis è equivalente a robuststab ma si utilizza per la performance
%nominale
[stabmarg, destabunc, info] = robustperf(Mf, opt)