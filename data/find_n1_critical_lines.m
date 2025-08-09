function critical_lines = find_n1_critical_lines(mpc)
% Find critical lines that violate N-1 criterion in DC power flow
% mpc: MATPOWER case struct (baseMVA, bus, branch, gen)
% Output: critical_lines = vector of branch indices that must stay connected

define_constants;
mpc = loadcase('case24_ieee_rts');
nl = size(mpc.branch, 1);
critical_lines = [];

% Loop through each branch
for l = 1:nl
    mpc_test = mpc;
    % Remove branch l (set status to 0)
    mpc_test.branch(l, BR_STATUS) = 0;
    
    % Run DC power flow
    results = rundcpf(mpc_test, mpoption('verbose', 0, 'out.all', 0));
    
    % --- 1) Check islanding ---
    % If voltage angles contain NaN, likely islanded
    if any(isnan(results.bus(:, VA)))
        critical_lines(end+1) = l;
        continue;
    end
    
    % --- 2) Check overloads ---
    flow = results.branch(:, PF);  % MW
    limit = results.branch(:, RATE_A);
    if any(abs(flow) > limit + 1e-6)
        critical_lines(end+1) = l;
        continue;
    end
end

fprintf('Critical lines (must remain connected for N-1): %s\n', mat2str(critical_lines));

end
