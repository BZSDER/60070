function [ots_result, switches] = run_dc_ots(mpc)
% DC Optimal Transmission Switching using YALMIP + Gurobi

define_constants;
nb = size(mpc.bus, 1);     % number of buses
nl = size(mpc.branch, 1);  % number of branches
ng = size(mpc.gen, 1);     % number of generators

branch = mpc.branch;
gen = mpc.gen;
bus = mpc.bus;
baseMVA = mpc.baseMVA;

f = branch(:, F_BUS);       % from-bus of each branch
t = branch(:, T_BUS);       % to-bus of each branch
x = branch(:, BR_X);        % reactance
rateA = branch(:, RATE_A);  % branch rating
Cg = mpc.gencost(:, 6);     % linear generation cost

% === Decision variables ===
Pg = sdpvar(ng, 1);         % generator output
theta = sdpvar(nb, 1);      % bus phase angle
Pf_pu = sdpvar(nl, 1);         % branch power flow
Pf = Pf_pu * baseMVA;
w = binvar(nl, 1);          % branch switch status (1=on, 0=off)
% delta = sdpvar(nl, 1);      % phase angle difference across each branch

Pd = bus(:, PD) ;  % load at each bus (normalized)
% M = 50;                   % Big-M value
BigM = compute_bigM_shortestpath(mpc, 1.1);
constraints = [];
% fprintf('OTS优化时总负荷 = %.2f MW\n', sum(bus(:,PD)));
%% Constrant 1: Generator output limits: Pg ∈ [Pmin, Pmax] (5)
for g = 1:ng
    constraints = [constraints, Pg >= gen(:,PMIN)];
    constraints = [constraints, Pg <= gen(:,PMAX)];
end

%% constraint 2: Branch power flow constraints (9)
    %input - output + generation = demand
for i = 1:nb
    input = 0;
    output = 0;

    % input & output from bus i (accumulated)
    for l = 1:nl
        if t(l) == i
            input = input + Pf(l);  % input to bus i (ji)
        end
        if f(l) == i
            output = output - Pf(l);  % output from bus i (ij)
        end
    end

    % accumulate on the generation
    Pg_sum = 0;
    for g = 1:ng
        if gen(g, GEN_BUS) == i
            Pg_sum = Pg_sum + Pg(g);
        end
    end

    % constraints on power flow
    constraints = [constraints, input - output + Pg_sum == Pd(i)];
    constraints = [constraints, sum(Pg) == sum(Pd)];
    
end

%% constraint 3: KVL at each bus (10)
for l = 1:nl
    from = f(l);
    to = t(l);
    
    % | xij * f - (theta_i - theta_j) | <= M (1 - w)
    % constraints = [constraints, ...
    %     abs(x(l) * Pf(l) - (theta(from) - theta(to))) <= M * (1 - w(l))];
    constraints = [constraints, ...
        abs(x(l)*Pf(l)/baseMVA - (theta(from)-theta(to))) <= BigM(l)*(1-w(l))]; 
end

%% constraint 4: Reference bus: set one angle to 0 (slack bus) (6)
ref_bus = bus(:, BUS_TYPE) == 3;
constraints = [constraints, theta(ref_bus) == 0];

%% constraint 5: limitation for branch power flow (11)
for l = 1:nl
      
    % | fij,y | <= wij,y (fij)
    constraints = [constraints, abs( Pf(l) ) <= rateA(l) * w(l)];
end
 
%% constraint 6: lines in branch must be disconnected by their numbers (12)
branch_group = containers.Map();  % Create a map to hold grouped branch indices

for l = 1:nl
    i = f(l);        % from-bus
    j = t(l);        % to-bus

    % Make the key direction-independent (i,j same as j,i)
    if i < j
        key = sprintf('%d_%d', i, j);
    else
        key = sprintf('%d_%d', j, i);
    end

    % Append the branch index to its corresponding node-pair group
    if isKey(branch_group, key)
        branch_group(key) = [branch_group(key), l];
    else
        branch_group(key) = l;
    end
end

% === Add switching-order constraints: w_{ij,y} ≤ w_{ij,y-1} ===
keys_list = keys(branch_group);
for k = 1:length(keys_list)
    key = keys_list{k};
    idx = sort(branch_group(key));  % Sort branch indices for this (i,j) group

    if length(idx) < 2
        continue;  % Only one branch between this pair, no constraint needed
    end

    % Enforce switching order: a later branch can only be switched ON
    % if the earlier one is also ON
    for y = 2:length(idx)
        l_now = idx(y);     % Current branch index
        l_prev = idx(y-1);  % Previous branch index
        constraints = [constraints, w(l_now) <= w(l_prev)];
    end
end

%% === 人工流平衡约束 (18) ===
h = sdpvar(nl, 1);   % artificial flow (可以正负)
H = sdpvar(nb, 1);   % root indicator

for i = 1:nb
    inflow  = sum(h(t == i));  % j→i
    outflow = sum(h(f == i));  % i→j
    constraints = [constraints, inflow - outflow + H(i) == 1];
end

%% === 人工流容量约束 (19) ===
for l = 1:nl
    constraints = [constraints, abs(h(l)) <= (nb-1) * w(l)];
end

%% === 人工流根节点约束 (20)(21) ===
ref_idx = find(bus(:, BUS_TYPE) == 3);
for i = 1:nb
    if i == ref_idx
        constraints = [constraints, H(i) == nb]; % H_ref = |Ωb|
    else
        constraints = [constraints, H(i) == 0];
    end
end

%% 强制关键支路必须连通（防止断主干支路）
critical_lines = [7, 11, 27];  % 可按系统修改
% constraints = [constraints, w(critical_lines) == 1];
% 
% %%  总体网络限制（最少支路数 & 最多断线数）
% constraints = [constraints, sum(w) >= ceil(0.80 * nl)];
constraints = [constraints, sum(1 - w) <= 5];

%%  目标函数：最小发电成本 + 断线惩罚 (7)
alpha = 1e-3;
objective = Cg' * Pg + alpha * sum(1 - w);

% === 求解 ===
options = sdpsettings('solver', 'gurobi', 'verbose', 0);
result = optimize(constraints, objective, options);

% === 输出结果 ===
ots_result.success = (result.problem == 0);
ots_result.Pg = value(Pg);
ots_result.Pf = value(Pf);
ots_result.theta = value(theta);
ots_result.z = value(w);
ots_result.fval = value(objective);
switches = round(value(w));

end

