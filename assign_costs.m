function mpc = assign_costs(mpc)
% 为 MATPOWER case 自动分配发电机类型、成本和基础可靠性
% 输出：
%   mpc.gencost(:,6) = 边际成本 £/MWh
%   mpc.gen_lambda   = 每台机组失效率 λ 次/年
%   mpc.gen_mu       = 每台机组修复率 μ /年
%   mpc.gen_type     = 机组类型标签

    ng = size(mpc.gen, 1);  % 总发电机数

    %% ===== 配置机组比例（可修改）=====
    ratio_wind   = 0.5;  % 风电/光伏比例
    ratio_nuclear= 0;  % 核电比例
    ratio_thermal= 0.5;  % 燃气/火电比例
    % 保证总比例为1，可根据需要手动调整
    if abs(ratio_wind+ratio_nuclear+ratio_thermal-1) > 1e-6
        error('机组比例之和必须为 1，请检查配置！');
    end

    %% ===== 根据比例计算每类机组数量 =====
    n_wind    = floor(ratio_wind * ng);
    n_nuclear = floor(ratio_nuclear * ng);
    n_thermal = ng - n_wind - n_nuclear;  % 剩余全部给火电

    % 分组索引
    idx1 = 1:n_wind;
    idx2 = n_wind+1 : n_wind+n_nuclear;
    idx3 = n_wind+n_nuclear+1 : ng;

    %% ===== 初始化成本矩阵 gencost =====
    gencost = zeros(ng, 6);
    gencost(:,1) = 2;   % MODEL = 2 (polynomial)
    gencost(:,2) = 0;   % STARTUP
    gencost(:,3) = 0;   % SHUTDOWN
    gencost(:,4) = 2;   % NCOST = 2  (linear)
    gencost(:,5) = 0;   % c2 = 0
    % c1 = price (£/MWh)
    gencost(idx1,6) = 0;     % Wind/PV
    gencost(idx2,6) = 15.0;  % Nuclear
    gencost(idx3,6) = 60.0;  % Thermal

    mpc.gencost = gencost;

    %% ===== 基础可靠性参数分配 =====
    gen_lambda = zeros(ng,1);  % 次/年
    gen_mu     = zeros(ng,1);  % /年
    gen_type   = strings(ng,1);

    % 风电（中等可靠性，修复快）
    gen_lambda(idx1) = 0.05;
    gen_mu(idx1)     = 12;
    gen_type(idx1)   = "Wind/PV";

    % 核电（极高可靠性，修复慢）
    gen_lambda(idx2) = 0.005;
    gen_mu(idx2)     = 4;
    gen_type(idx2)   = "Nuclear";

    % 火电（一般可靠性，修复中等）
    gen_lambda(idx3) = 0.02;
    gen_mu(idx3)     = 10;
    gen_type(idx3)   = "Thermal";

    % 保存到 mpc
    mpc.gen_lambda = gen_lambda;
    mpc.gen_mu = gen_mu;
    mpc.gen_type = gen_type;

    %% ===== 打印分组信息 =====
    fprintf('\n📋 发电机分组完成：\n');
    fprintf('  风电机组数 = %d\n', n_wind);
    fprintf('  核电机组数 = %d\n', n_nuclear);
    fprintf('  火电机组数 = %d\n', n_thermal);
    fprintf('  总机组数   = %d\n', ng);
end
