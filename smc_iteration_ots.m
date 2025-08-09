function [gap, lolp_flag, valid_flag, cost] = smc_iteration_ots(mpc, scenario, nb, ng, nl)
    define_constants;

    sample = mpc;

    %% === 负荷扰动 ===
    sample.bus(:, PD) = sample.bus(:, PD) .* scenario.load_factor;

    %% === 支路可用性 ===
    lambda_b = scenario.lambda_factor_branch .* 0.1;
    mu_b     = 10;
    R_branch = mu_b ./ (lambda_b + mu_b);
    line_status = rand(nl,1) < R_branch;
    sample.branch(:, BR_STATUS) = sample.branch(:, BR_STATUS) .* line_status;

    %% === 机组可用性 ===
    gen_status = zeros(ng,1);
    for g = 1:ng
        lambda_g = scenario.lambda_factor_gen .* mpc.gen_lambda(g);
        mu_g = mpc.gen_mu(g);
        Rg = mu_g ./ (lambda_g + mu_g);
        gen_status(g) = rand < Rg;
    end
    sample.gen(:, GEN_STATUS) = sample.gen(:, GEN_STATUS) .* gen_status;

    %% === 风电机组风速不可用性 ===
    P_wind_unavail = 0.1;
    wind_idx = find(mpc.gen_type == "Wind/PV");
    if ~isempty(wind_idx)
        wind_status = rand(numel(wind_idx),1) > P_wind_unavail;
        sample.gen(wind_idx, GEN_STATUS) = sample.gen(wind_idx, GEN_STATUS) .* wind_status;
    end

    %% === OTS 优化 ===
    try
        [ots_result, switches] = run_dc_ots(sample);
        if ~isempty(switches)
            sample.branch(:, BR_STATUS) = round(switches);
        end
    catch
        % 忽略 OTS 错误
    end

    %% === 潮流计算（与基准版 gap 计算保持一致） ===
    try
        r = rundcopf(sample, mpoption('verbose',0,'out.all',0));
        total_load = sum(sample.bus(:,PD));

        if ~r.success || sum(abs(r.branch(:,PF))) < 1e-3
            % 基准版这里用 avail_cap 计算缺口
            avail_cap = sum(sample.gen(sample.gen(:,GEN_STATUS) > 0, PMAX));
            gap = max(0, total_load - avail_cap);   % <<< 对齐基准版
            lolp_flag = 1;
            valid_flag = 0;
            cost = NaN;
        else
            total_gen = sum(r.gen(:,PG));
            if total_gen == 0
                avail_cap = sum(sample.gen(sample.gen(:,GEN_STATUS) > 0, PMAX));
                gap = max(0, total_load - avail_cap);  % <<< 对齐基准版
                lolp_flag = 1;
                valid_flag = 0;
                cost = NaN;
            else
                gap = max(0, total_load - total_gen);  % <<< 对齐基准版
                lolp_flag = gap > 1e-6;
                valid_flag = gap <= 1e-6;
                cost = sum(mpc.gencost(:,6) .* r.gen(:,PG));
            end
        end
    catch
        total_load = sum(sample.bus(:,PD));
        avail_cap = sum(sample.gen(sample.gen(:,GEN_STATUS) > 0, PMAX));
        gap = max(0, total_load - avail_cap);  % <<< 对齐基准版
        lolp_flag = 1;
        valid_flag = 0;
        cost = NaN;
    end
end

