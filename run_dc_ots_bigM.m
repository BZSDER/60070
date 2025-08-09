
function [ots_result, switches] = run_dc_ots(mpc)
% 使用 YALMIP + Gurobi 执行 DC Optimal Transmission Switching (OTS)
% 使用 Big-M 线性化建模支路开关控制
% 输入: mpc - MATPOWER case
% 输出: ots_result - 优化结果结构体
%         switches - 每条支路的开关状态（0/1）

define_constants;
nb = size(mpc.bus, 1);      % 节点数
nl = size(mpc.branch, 1);   % 支路数
ng = size(mpc.gen, 1);      % 发电机数

% 参数提取
branch = mpc.branch;
gen = mpc.gen;
bus = mpc.bus;
baseMVA = mpc.baseMVA;

f = branch(:, F_BUS);  % 支路起点
t = branch(:, T_BUS);  % 支路终点
x = branch(:, BR_X);   % 电抗
rateA = branch(:, RATE_A);
Cg = mpc.gencost(:, 5);  % 发电成本（线性）

% 决策变量
Pg = sdpvar(ng, 1);               % 发电出力
theta = sdpvar(nb, 1);           % 相角
x_sw = binvar(nl, 1);            % 支路开关状态（二元变量）
Pf = sdpvar(nl, 1);              % 支路潮流

% 构建发电机映射矩阵 G
G = zeros(nb, ng);
for i = 1:ng
    G(gen(i, GEN_BUS), i) = 1;
end

% 节点注入矩阵 A
A = sparse([f; t], (1:nl)'*[1;1], [-1;1], nb, nl);

% 负荷向量
Pd = bus(:, PD) / baseMVA;

% Big-M 参数
M = 100;

% 构建约束
constraints = [];

% 发电机限制
Pmax = gen(:, PMAX);
Pmin = gen(:, PMIN);
constraints = [constraints, Pmin <= Pg <= Pmax];

% 支路功率与相角差线性化 (Big-M)
for i = 1:nl
    Bij = 1 / x(i);
    delta = theta(f(i)) - theta(t(i));

    constraints = [constraints, ...
        Pf(i) - Bij * delta <= M * (1 - x_sw(i)), ...
        Pf(i) - Bij * delta >= -M * (1 - x_sw(i)), ...
        Pf(i) <= rateA(i) * x_sw(i), ...
        Pf(i) >= -rateA(i) * x_sw(i)];
end

% 功率平衡
constraints = [constraints, G * Pg - Pd == A * Pf];

% 参考母线
ref_bus = find(bus(:, BUS_TYPE) == 3);
constraints = [constraints, theta(ref_bus) == 0];

% 目标函数：最小发电成本 + 开关惩罚
alpha = 1e-3;
objective = Cg' * Pg + alpha * sum(1 - x_sw);

% 优化器设置
options = sdpsettings('solver', 'gurobi', 'verbose', 0);
result = optimize(constraints, objective, options);

% 输出结果
ots_result.success = (result.problem == 0);
ots_result.Pg = value(Pg);
ots_result.Pf = value(Pf);
ots_result.theta = value(theta);
ots_result.z = value(x_sw);

switches = round(value(x_sw));
end
