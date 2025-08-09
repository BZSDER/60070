function [metrics, trends] = smc_simulation_loop(mpc, N, scenario, env_type)
    define_constants;
    rng(42);

    EENS = 0; LOLP = 0; valid_samples = 0;
    nb = size(mpc.bus,1); ng = size(mpc.gen,1); nl = size(mpc.branch,1);

    % 收敛向量
    LOLP_vec = zeros(N,1); EENS_vec = zeros(N,1);
    SAIFI_vec = zeros(N,1); SAIDI_vec = zeros(N,1);
    cost_vec = zeros(N,1);

    for k = 1:N
        sample = mpc;

        % === 负荷环境扰动 ===
        sample.bus(:, PD) = sample.bus(:, PD) * scenario.load_factor;

        % === 支路可靠性抽样 ===
        lambda_b = scenario.lambda_factor_branch * 0.1; % 基础支路λ
        mu_b     = 10;                                  % 基础支路μ
        R_branch = mu_b / (lambda_b + mu_b);
        line_status = rand(nl,1) < R_branch;
        sample.branch(:, BR_STATUS) = sample.branch(:, BR_STATUS) .* line_status;

        % === 机组可靠性抽样 ===
        gen_status = zeros(ng,1);
        for g = 1:ng
            lambda_g = scenario.lambda_factor_gen * mpc.gen_lambda(g);
            mu_g = mpc.gen_mu(g);
            Rg = mu_g / (lambda_g + mu_g);
            gen_status(g) = rand < Rg;
        end
        sample.gen(:, GEN_STATUS) = sample.gen(:, GEN_STATUS) .* gen_status;

        % === 风电机组风速不可用性抽样 ===
        P_wind_unavail = 0.1;  % 风速不足导致机组停机的概率，可调
        wind_idx = find(mpc.gen_type == "Wind/PV");

        if ~isempty(wind_idx)
            % 对每台风电机组随机判断风速是否足够
            wind_status = rand(numel(wind_idx),1) > P_wind_unavail;
            % 覆盖风电机组状态（和原有可靠性叠加）
            sample.gen(wind_idx, GEN_STATUS) = sample.gen(wind_idx, GEN_STATUS) .* wind_status;
        end
        
        % === 潮流计算 ===
        try
    r = rundcopf(sample, mpoption('verbose',0,'out.all',0)); %%

    total_load = sum(sample.bus(:,PD));  % 提前计算总负荷  % <<< 新增

    if ~r.success || sum(abs(r.branch(:,PF)))<1e-3
        LOLP = LOLP + 1;
        % 原来是 EENS = EENS + total_load
        % 改成按可用机组容量上限估算缺口                 % <<< 修改
        avail_cap = sum(sample.gen(sample.gen(:,GEN_STATUS)>0, PMAX));
        gap = max(0, total_load - avail_cap);
        EENS = EENS + gap;
        cost_vec(k) = NaN;
    else
        total_gen  = sum(r.gen(:,PG));

        if total_gen==0
            LOLP = LOLP + 1;
            avail_cap = sum(sample.gen(sample.gen(:,GEN_STATUS)>0, PMAX)); % <<< 新增
            gap = max(0, total_load - avail_cap);                          % <<< 修改
            EENS = EENS + gap;
            cost_vec(k) = NaN;
        else
            valid_samples = valid_samples+1;
            gap = max(0, total_load - total_gen);                          % <<< 修改
            EENS = EENS + gap;
            cost_vec(k) = sum(mpc.gencost(:,6).*r.gen(:,PG));
        end
    end
    catch
        LOLP = LOLP + 1;
        total_load = sum(sample.bus(:,PD));
        avail_cap = sum(sample.gen(sample.gen(:,GEN_STATUS)>0, PMAX));         % <<< 新增
        gap = max(0, total_load - avail_cap);                                  % <<< 修改
        EENS = EENS + gap;
        cost_vec(k) = NaN;
    end

        % 收敛向量
        LOLP_vec(k)  = LOLP/k;
        EENS_vec(k)  = (EENS/k)*8760;
        SAIFI_vec(k) = (LOLP/k)*8760;
        SAIDI_vec(k) = (LOLP/k)*8760;
    end

    % === 指标输出 ===
    metrics.EENS  = EENS_vec(end);
    metrics.LOLP  = LOLP_vec(end);
    metrics.SAIFI = SAIFI_vec(end);
    metrics.SAIDI = SAIDI_vec(end);
    metrics.avg_cost = mean(cost_vec(~isnan(cost_vec)));

    trends.LOLP = LOLP_vec; trends.EENS = EENS_vec;
    trends.SAIFI = SAIFI_vec; trends.SAIDI = SAIDI_vec;
    trends.cost_vec = cost_vec;

    fprintf('\n📊 SMC Summary (%d samples, env: %s):\n', N, env_type);
    fprintf('✅ Valid Samples     : %d\n', valid_samples);
    fprintf('❌ Load Loss Events  : %d\n', LOLP);
    fprintf('📉 EENS (annual)     : %.2f MW·h/year\n', metrics.EENS);
    fprintf('📈 LOLP              : %.6f (per hour)\n', metrics.LOLP);
    fprintf('⏱️ SAIDI (annual)    : %.2f hrs/user/year\n', metrics.SAIDI);
    fprintf('🔁 SAIFI (annual)    : %.2f times/user/year\n', metrics.SAIFI);
    fprintf('💰 Avg Gen Cost      : %.2f £\n', metrics.avg_cost);
end



