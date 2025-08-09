function mpc = apply_environmental_factors(mpc, env_type)
    define_constants;

    switch lower(env_type)
        case 'normal'
        case 'hot'
            fprintf('High temperature，system rating decrease: 20%%\n');
            mpc.branch(:, RATE_A) = 0.8 * mpc.branch(:, RATE_A);
        case 'cold'
            fprintf('Low temperature，system load increase: 15%%\n');
            mpc.bus(:, PD) = 1.15 * mpc.bus(:, PD);
        otherwise
            warning('unknown "%s"，keep case normal', env_type);
    end
end