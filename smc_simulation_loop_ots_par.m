function [metrics, trends] = smc_simulation_loop_ots_par(mpc, N, scenario, env_type)
    define_constants;
    rng(42);

    nb = size(mpc.bus,1); 
    ng = size(mpc.gen,1); 
    nl = size(mpc.branch,1);

    % === 向量预分配（并行累积用） ===
    LOLP_vec = zeros(N,1); 
    EENS_vec = zeros(N,1);
    SAIFI_vec = zeros(N,1); 
    SAIDI_vec = zeros(N,1);
    cost_vec = NaN(N,1);         % NaN 表示该样本无效
    sample_LOLP = zeros(N,1);    % 每个样本是否失负荷
    sample_EENS = zeros(N,1);    % 每个样本失负荷电量

    % === 打开并行池（如果未打开）===
    if isempty(gcp('nocreate'))
        parpool('local', 6);  % 6核CPU
    end

    % === 并行主循环 ===
    parfor k = 1:N
        sample = mpc;

        % --- 负荷扰动 ---
        sample.bus(:, PD) = sample.bus(:, PD) * scenario.load_factor;

        % --- 支路可靠性抽样 ---
        lambda_b = scenario.lambda_factor_branch * 0.1;
        mu_b     = 10;
        R_branch = mu_b / (lambda_b + mu_b);
        line_status = rand(nl,1) < R_branch;
        sample.branch(:, BR_STATUS) = sample.branch(:, BR_STATUS) .* line_status;

        % --- 机组可靠性抽样 ---
        gen_status = zeros(ng,1);
        for g = 1:ng
            lambda_g = scenario.lambda_factor_gen * mpc.gen_lambda(g);
            mu_g = mpc.gen_mu(g);
            Rg = mu_g / (lambda_g + mu_g);
            gen_status(g) = rand < Rg;
        end
        sample.gen(:, GEN_STATUS) = sample.gen(:, GEN_STATUS) .* gen_status;

        % --- 动态 OTS ---
        try
            [ots_result, switches] = run_dc_ots(sample);
            if ~isempty(switches)
                sample.branch(:, BR_STATUS) = round(switches);
            end
        catch
            % OTS失败时保持原始状态
        end

        % --- 潮流计算 ---
        try
            r = rundcpf(sample, mpoption('verbose',0,'out.all',0));
            total_load = sum(sample.bus(:,PD));
            total_gen  = sum(r.gen(:,PG));

            if ~r.success || total_gen==0 || sum(abs(r.branch(:,PF)))<1e-3
                sample_LOLP(k) = 1;
                sample_EENS(k) = total_load;
            else
                deficit = max(0,total_load-total_gen);
                sample_LOLP(k) = deficit>0;
                sample_EENS(k) = deficit;
                cost_vec(k) = sum(mpc.gencost(:,6).*r.gen(:,PG));
            end
        catch
            sample_LOLP(k) = 1;
            sample_EENS(k) = sum(sample.bus(:,PD));
        end
    end

    % === 汇总指标 ===
    LOLP_cum = cumsum(sample_LOLP);
    EENS_cum = cumsum(sample_EENS);

    for k = 1:N
        LOLP_vec(k)  = LOLP_cum(k)/k;
        EENS_vec(k)  = (EENS_cum(k)/k)*8760;
        SAIFI_vec(k) = (LOLP_cum(k)/k)*8760;
        SAIDI_vec(k) = (LOLP_cum(k)/k)*8760;
    end

    metrics.EENS  = EENS_vec(end);
    metrics.LOLP  = LOLP_vec(end);
    metrics.SAIFI = SAIFI_vec(end);
    metrics.SAIDI = SAIDI_vec(end);
    metrics.avg_cost = mean(cost_vec(~isnan(cost_vec)));

    trends.LOLP = LOLP_vec; 
    trends.EENS = EENS_vec;
    trends.SAIFI = SAIFI_vec; 
    trends.SAIDI = SAIDI_vec;
    trends.cost_vec = cost_vec;

    fprintf('\n📊 并行 OTS SMC Summary (%d samples, env: %s):\n', N, env_type);
    fprintf('✅ Valid Samples     : %d\n', sum(~isnan(cost_vec)));
    fprintf('❌ Load Loss Events  : %d\n', sum(sample_LOLP));
    fprintf('📉 EENS (annual)     : %.2f MW·h/year\n', metrics.EENS);
    fprintf('📈 LOLP              : %.6f (per hour)\n', metrics.LOLP);
    fprintf('⏱️ SAIDI (annual)    : %.2f hrs/user/year\n', metrics.SAIDI);
    fprintf('🔁 SAIFI (annual)    : %.2f times/user/year\n', metrics.SAIFI);
    fprintf('💰 Avg Gen Cost      : %.2f £\n', metrics.avg_cost);
end
