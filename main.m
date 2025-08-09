clc; clear;
define_constants;

%% ===== 初始化运行环境 =====
init_environment;
addpath(genpath('G:\SCHDOCS\60070\matlab_code\ieee24bus_ots_S_island'));
if isempty(gcp('nocreate'))
    pool = parpool('local', 4);  % 启动并行池并返回对象
else
    pool = gcp('nocreate');      % 获取已启动的并行池对象
end
% 把迭代函数文件分发到所有 worker
addAttachedFiles(pool, {which('smc_iteration_ots.m')});

%% ===== 场景设置 =====
env_type = 'normal';  % 可选：'normal' / 'storm' / 'cold' / 'hot'

%% ===== 加载模型并自动分配成本 =====
mpc_base = loadcase('case24_ieee_rts');
mpc_base.bus(:, PD) = mpc_base.bus(:, PD) * (2850/2850); %设定pd
mpc_base = assign_costs(mpc_base);  % 自动分配发电成本（gencost第6列）

%% ===== 加载场景参数 =====
scenarios = scenario_library();
scenario = scenarios.(env_type);

%% === 基准系统（未优化）模拟 ===
fprintf('🔹 基准系统（未优化）计算中...\n');

% 基准OPF静态成本
r_base = rundcopf(mpc_base, mpoption('verbose',0,'out.all',0));
if r_base.success
    base_cost = sum(mpc_base.gencost(:,6) .* r_base.gen(:,PG));
else
    base_cost = NaN;
end

% 基准SMC模拟（年化指标）
[metrics_base, trends_base] = smc_simulation_loop(mpc_base, 8000, scenario, env_type);

%% ===== OTS 优化系统 =====
fprintf(' 执行 OTS 优化...\n');
[ots_result, switches] = run_dc_ots(mpc_base);
mpc_ots = mpc_base;
mpc_ots.branch(:, BR_STATUS) = round(switches);
mpc_ots.gen(:, PG) = ots_result.Pg;

ots_cost = ots_result.fval;

% % OTS后SMC模拟（年化指标）
% [metrics_ots, trends_ots] = smc_simulation_loop(mpc_ots, 20000, scenario, env_type);

%% ===== OTS 优化系统(动态) =====
fprintf('🔹 动态 OTS（每次迭代前）SMC 模拟...\n');

% 调用新的 SMC 循环函数，每次迭代执行一次 OTS
[metrics_ots_dynamic, trends_ots_dynamic] = smc_simulation_loop_ots(mpc_base, 8000, scenario, env_type);
metrics_ots = metrics_ots_dynamic;
trends_ots  = trends_ots_dynamic;

%% === 汇总对比表格（全部年化指标）===
comparison = table( ...
    ["Base"; "OTS"], ...
    [base_cost; ots_cost], ...
    [metrics_base.avg_cost; metrics_ots.avg_cost], ...  
    [metrics_base.EENS; metrics_ots.EENS], ...
    [metrics_base.LOLP; metrics_ots.LOLP], ...
    [metrics_base.SAIDI; metrics_ots.SAIDI], ...
    [metrics_base.SAIFI; metrics_ots.SAIFI], ...
    'VariableNames', {'Case','StaticCost','ActualCost_£','EENS_MWh_yr','LOLP_hr','SAIDI_hr_yr','SAIFI_times_yr'} );

disp('=== OTS优化前后对比表（年化指标） ===');
disp(comparison);

%% === 保存对比结果 ===
folder = ['results/compare_', env_type, '_', datestr(now,'yyyymmdd_HHMM')];
if ~exist(folder,'dir'); mkdir(folder); end
writetable(comparison, fullfile(folder,'comparison.csv'));

%% === 绘制柱状对比图（年化指标） ===
figure('Name','OTS前后指标对比','NumberTitle','off');

% 数据矩阵（每列一个案例）
bar_data = [
    base_cost,       ots_cost;
    metrics_base.avg_cost, metrics_ots.avg_cost;
    metrics_base.EENS,  metrics_ots.EENS;
    metrics_base.LOLP,  metrics_ots.LOLP;
    metrics_base.SAIDI, metrics_ots.SAIDI;
    metrics_base.SAIFI, metrics_ots.SAIFI
];

titles = { ...
    'Static Cost (£)', ...
    'Actual Cost (£)', ...
    'EENS (MWh/year)', ...
    'LOLP (per hour)', ...
    'SAIDI (hrs/user/year)', ...
    'SAIFI (times/user/year)'};

for i = 1:6
    subplot(2,3,i);
    bar(bar_data(i,:)); 
    set(gca,'XTickLabel',{'Base','OTS'});
    title(titles{i});

    base_val = bar_data(i,1);
    ots_val  = bar_data(i,2);

    % 百分比变化
    if base_val ~= 0
        pct_change = (ots_val - base_val) / base_val * 100;
    else
        pct_change = NaN;
    end

    % === 根据不同指标控制小数位数 ===
    if i == 4  % LOLP
        base_fmt = '%.6f';
        ots_fmt  = '%.6f (%.1f%%)';
    else
        base_fmt = '%.2f';
        ots_fmt  = '%.2f (%.1f%%)';
    end

    % Base柱标签
    text(1, base_val, sprintf(base_fmt, base_val), ...
         'HorizontalAlignment','center', ...
         'VerticalAlignment','bottom', ...
         'FontSize',9);

    % OTS柱标签
    text(2, ots_val, sprintf(ots_fmt, ots_val, pct_change), ...
         'HorizontalAlignment','center', ...
         'VerticalAlignment','bottom', ...
         'FontSize',9);
end

sgtitle(['OTS优化前后对比（绝对值 + 相对变化） - 环境: ', env_type]);

%% === 绘制SMC收敛曲线对比（年化指标） ===
samples_base = 1:length(trends_base.LOLP);
samples_ots  = 1:length(trends_ots.LOLP);

figure('Name','SMC收敛曲线对比','NumberTitle','off');

subplot(2,2,1); plot(samples_base, trends_base.LOLP, 'b', 'LineWidth', 1.5); hold on;
plot(samples_ots, trends_ots.LOLP, 'r', 'LineWidth', 1.5);
title('LOLP convergence'); xlabel('number of samples'); ylabel('LOLP(per hour)'); legend('Base','OTS');

subplot(2,2,2); plot(samples_base, trends_base.EENS, 'b', 'LineWidth', 1.5); hold on;
plot(samples_ots, trends_ots.EENS, 'r', 'LineWidth', 1.5);
title('EENS convergence '); xlabel('number of samples'); ylabel('EENS(MWh/year)'); legend('Base','OTS');

subplot(2,2,3); plot(samples_base, trends_base.SAIFI, 'b', 'LineWidth', 1.5); hold on;
plot(samples_ots, trends_ots.SAIFI, 'r', 'LineWidth', 1.5);
title('SAIFI convergence '); xlabel('number of samples'); ylabel('SAIFI(times/year)'); legend('Base','OTS');

subplot(2,2,4); plot(samples_base, trends_base.SAIDI, 'b', 'LineWidth', 1.5); hold on;
plot(samples_ots, trends_ots.SAIDI, 'r', 'LineWidth', 1.5);
title('SAIDI convergence '); xlabel('number of samples'); ylabel('SAIDI(hours/year)'); legend('Base','OTS');

sgtitle(['SMC收敛曲线对比 (年化指标) - 环境: ', env_type]);

%% ===  输出每个母线的各机组出力 ===
Pg_result = ots_result.Pg;       % 每台机组的出力(MW)
gen_bus   = mpc_base.gen(:, GEN_BUS);
nb        = size(mpc_base.bus, 1);

fprintf('\n📊 各母线发电机出力情况（MW）：\n');
Pg_table = [];

for i = 1:nb
    idx = find(gen_bus == i);  % 母线i上的机组
    if ~isempty(idx)
        fprintf('母线 %d: ', i);
        fprintf('%.2f ', Pg_result(idx));
        fprintf('\n');

        % 追加到导出表格
        bus_col  = repmat(i, length(idx), 1);
        gen_col  = idx(:);
        pg_col   = Pg_result(idx);
        Pg_table = [Pg_table; [bus_col, gen_col, pg_col]];
    end
end

% 保存为 CSV
T_Pg = array2table(Pg_table, 'VariableNames', {'Bus','GenID','Pg_MW'});
writetable(T_Pg, fullfile(folder, 'generator_output_per_bus.csv'));
fprintf('✅ 各母线机组出力已保存到 generator_output_per_bus.csv\n');

%% === 保存发电机类型信息 ===
gen_costs = mpc_base.gencost(:,6);
ng = length(gen_costs);
gen_bus = mpc_base.gen(:,GEN_BUS);

% 定义类型（和 assign_costs.m 一致）
gen_type = strings(ng,1);
for i = 1:ng
    if gen_costs(i) <= 10
        gen_type(i) = "风电/光伏(可再生)";
    elseif gen_costs(i) <= 20
        gen_type(i) = "核电";
    else
        gen_type(i) = "燃气/常规火电";
    end
end

% 输出到命令行
fprintf('\n📋 发电机类型列表:\n');
for i = 1:ng
    fprintf('  - 发电机 %d: Bus %d, 成本 %.2f £/MWh → 类型: %s\n', ...
        i, gen_bus(i), gen_costs(i), gen_type(i));
end

% 保存为 CSV
T_gen = table((1:ng)', gen_bus, gen_costs, gen_type, ...
    'VariableNames', {'GenID','Bus','Cost_£_MWh','Type'});
writetable(T_gen, fullfile(folder,'generator_list.csv'));

%% ===  保存OTS断开支路列表 ===
opened_lines = find(round(switches) == 0);
if isempty(opened_lines)
    fprintf('\n✅ OTS优化后无支路断开，系统保持全接通。\n');
else
    fprintf('\n⚡ OTS优化后断开的支路（共 %d 条）：\n', length(opened_lines));
    for i = 1:length(opened_lines)
        f = mpc_base.branch(opened_lines(i), F_BUS);
        t = mpc_base.branch(opened_lines(i), T_BUS);
        fprintf('  - 支路 %d: Bus %d ↔ Bus %d\n', opened_lines(i), f, t);
    end
    writematrix(opened_lines, fullfile(folder,'opened_lines.csv'));
end

%% === 导出母线基准电压与实际电压 ===
define_constants;  % 确保BUS_I, VM, VA, BASE_KV可用

% 取优化后系统的bus矩阵
bus_data = mpc_ots.bus;

bus_id    = bus_data(:, BUS_I);       % 母线编号
base_kv   = bus_data(:, BASE_KV);     % 母线基准电压(kV)
vm_pu     = bus_data(:, VM);          % 电压幅值(p.u.)
va_deg    = bus_data(:, VA);          % 电压角度(deg)
actual_kv = vm_pu .* base_kv;         % 实际电压(kV)

% 命令行显示前几行
fprintf('\n📋 母线电压信息（前5条）:\n');
disp(table(bus_id(1:5), base_kv(1:5), vm_pu(1:5), actual_kv(1:5), ...
    'VariableNames', {'Bus','Base_kV','V_pu','V_actual_kV'}));

% 保存为CSV
T_bus = table(bus_id, base_kv, vm_pu, va_deg, actual_kv, ...
    'VariableNames', {'Bus','Base_kV','V_pu','V_angle_deg','V_actual_kV'});
writetable(T_bus, fullfile(folder,'bus_voltage_info.csv'));

fprintf('\n✅ 对比完成，表格和图像已保存到 %s\n', folder);

%% === 母线出力健康诊断 ===
fprintf('\n🔍 母线出力健康诊断:\n');

% 提取发电机信息（直接从 mpc_ots）
Pg = mpc_ots.gen(:, PG);      % 发电机出力
bus_gen = mpc_ots.gen(:, GEN_BUS);
nb = size(mpc_ots.bus,1);
bus_load = mpc_ots.bus(:, PD);  % 母线负荷

% 计算每个母线总出力
bus_gen_output = accumarray(bus_gen, Pg, [nb,1], @sum, 0);

% 计算裕度
bus_margin = bus_gen_output - bus_load;

% 母线状态判断
bus_status = strings(nb,1);
for i = 1:nb
    if bus_gen_output(i) == 0 && bus_load(i) > 0
        bus_status(i) = "受端(纯负荷)";
    elseif bus_margin(i) > 0.2*bus_load(i)
        bus_status(i) = "送端(供电富余)";
    elseif bus_margin(i) < -0.1*bus_load(i)
        bus_status(i) = "负荷紧张/依赖外供";
    else
        bus_status(i) = "本地平衡";
    end
end

% 输出前几条诊断信息
T_bus_diag = table((1:nb)', bus_gen_output, bus_load, bus_margin, bus_status, ...
    'VariableNames', {'Bus','Gen_MW','Load_MW','Margin_MW','Status'});

disp(T_bus_diag(1:min(10,nb),:));

% 保存为CSV
writetable(T_bus_diag, fullfile(folder,'bus_generation_diagnosis.csv'));

% 高亮潜在问题母线
problem_idx = find(bus_status ~= "送端(供电富余)" & bus_status ~= "本地平衡");
if isempty(problem_idx)
    fprintf('✅ 所有母线运行正常，无明显紧张点。\n');
else
    fprintf('⚠ 潜在问题母线列表: %s\n', mat2str(problem_idx'));
end

%% === 导出每条支路潮流信息 ===
branch_from = mpc_ots.branch(:, F_BUS);  % 起点母线
branch_to   = mpc_ots.branch(:, T_BUS);  % 终点母线
branch_rate = mpc_ots.branch(:, RATE_A); % 额定容量(MVA)
nl = size(mpc_ots.branch, 1);           % 支路数

Pf_result   = ots_result.Pf;             % 优化后的支路潮流(MW)

% 组合成表格
branch_table = table((1:nl)', branch_from, branch_to, Pf_result, branch_rate, ...
    abs(Pf_result)./branch_rate*100, ...
    'VariableNames', {'BranchID','FromBus','ToBus','PowerFlow_MW','RateA_MVA','Loading_%'});

% 打印前几行检查
disp('📊 支路潮流情况（前10条）：');
disp(branch_table(1:min(10,nl),:));

% 保存为 CSV
writetable(branch_table, fullfile(folder,'branch_power_flow.csv'));
fprintf('✅ 每条支路潮流已导出到 branch_power_flow.csv\n');


