function [metrics, trends] = smc_simulation_loop_ots(mpc, N, scenario, env_type)
    rng(42);

    nb = size(mpc.bus,1); 
    ng = size(mpc.gen,1); 
    nl = size(mpc.branch,1);

    batch_size = 100; % 每批运行样本数，可改
    num_batches = ceil(N / batch_size);

    %% === 自动确保迭代函数在 worker 可用 ===
    iter_file = which('smc_iteration_ots.m');
    if isempty(iter_file)
        error('找不到 smc_iteration_ots.m，请检查路径');
    end
    pool = gcp('nocreate');
    if isempty(pool)
        pool = parpool('local', 4);
        addAttachedFiles(pool, {iter_file});
    elseif ~ismember(iter_file, pool.AttachedFiles)
        addAttachedFiles(pool, {iter_file});
    end

    %% === 检查是否有历史数据（新增） ===
    if isfile('partial_results.mat')
        load('partial_results.mat', 'EENS_all', 'LOLP_all', 'valid_all', 'cost_all');
        fprintf('🔄 检测到历史数据，续跑模式启动：已完成 %d/%d 样本\n', length(EENS_all), N);
    else
        EENS_all  = [];
        LOLP_all  = [];
        valid_all = [];
        cost_all  = [];
    end

    %% === 分批运行 ===
    tic;
    while length(EENS_all) < N
        cur_batch_size = min(batch_size, N - length(EENS_all));
        fprintf('=== 批次 %d/%d: 本批运行 %d 样本 ===\n', ...
            ceil(length(EENS_all)/batch_size)+1, num_batches, cur_batch_size);

        parfor k = 1:cur_batch_size
            [EENS_tmp(k), LOLP_tmp(k), valid_tmp(k), cost_tmp(k)] = ...
                smc_iteration_ots(mpc, scenario, nb, ng, nl);
        end

        % 累积结果
        EENS_all  = [EENS_all;  EENS_tmp(:)];
        LOLP_all  = [LOLP_all;  LOLP_tmp(:)];
        valid_all = [valid_all; valid_tmp(:)];
        cost_all  = [cost_all;  cost_tmp(:)];

        % === 批次统计（新增cost） ===
        cur_N = length(EENS_all);
        cur_EENS = mean(EENS_all) * 8760;
        cur_LOLP = mean(LOLP_all);
        cur_cost = mean(cost_all(~isnan(cost_all)));
        fprintf('已完成 %d/%d 样本 | EENS=%.2f MWh/yr | LOLP=%.6f | Cost=%.2f £\n', ...
            cur_N, N, cur_EENS, cur_LOLP, cur_cost);

        % 保存中间进度
        save('partial_results.mat', 'EENS_all', 'LOLP_all', 'valid_all', 'cost_all');
    end
    elapsed_time = toc;

    %% === 汇总最终结果 ===
    metrics.EENS  = mean(EENS_all) * 8760;
    metrics.LOLP  = mean(LOLP_all);
    metrics.SAIFI = metrics.LOLP * 8760;
    metrics.SAIDI = metrics.LOLP * 8760;
    metrics.avg_cost = mean(cost_all(~isnan(cost_all)));

    %% === 收敛曲线 ===
    trends.LOLP  = cumsum(LOLP_all) ./ (1:length(LOLP_all))';
    trends.EENS  = cumsum(EENS_all) ./ (1:length(EENS_all))' * 8760;
    trends.SAIFI = trends.LOLP * 8760;
    trends.SAIDI = trends.LOLP * 8760;
    trends.cost_vec = cost_all;

    %% === 保存最终结果，删除中间文件 ===
    save('final_results.mat', 'metrics', 'trends', 'EENS_all', 'LOLP_all', 'valid_all', 'cost_all');
    if isfile('partial_results.mat')
        delete('partial_results.mat');
    end

    %% === 打印最终统计 ===
    fprintf('\n📊 SMC Summary (%d samples, env: %s):\n', N, env_type);
    fprintf('✅ Valid Samples     : %d\n', sum(valid_all));
    fprintf('❌ Load Loss Events  : %d\n', sum(LOLP_all));
    fprintf('📉 EENS (annual)     : %.2f MW·h/year\n', metrics.EENS);
    fprintf('📈 LOLP              : %.6f (per hour)\n', metrics.LOLP);
    fprintf('⏱️ SAIDI (annual)    : %.2f hrs/user/year\n', metrics.SAIDI);
    fprintf('🔁 SAIFI (annual)    : %.2f times/user/year\n', metrics.SAIFI);
    fprintf('💰 Avg Gen Cost      : %.2f £\n', metrics.avg_cost);
    fprintf('⏱️ 总耗时: %.2f 秒\n', elapsed_time);
end

