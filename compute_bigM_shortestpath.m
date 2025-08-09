function BigM = compute_bigM_shortestpath(mpc, safety_factor)
% Compute line-specific Big-M values using shortest-path reactance
% mpc: MATPOWER case
% safety_factor: e.g., 1.1

define_constants;
nb = size(mpc.bus, 1);
nl = size(mpc.branch, 1);

f = mpc.branch(:, F_BUS);
t = mpc.branch(:, T_BUS);
x = mpc.branch(:, BR_X);         % branch reactance
rateA = mpc.branch(:, RATE_A);   % MW
baseMVA = mpc.baseMVA;

% --- Step 1: Construct weighted graph with reactance ---
G = graph(f, t, x, nb);           % undirected graph (weight = reactance)
G = addedge(G, t, f, x);          % ensure undirected

% --- Step 2: Compute all-pairs shortest path (Dijkstra for each node) ---
shortestX = inf(nb, nb);
for i = 1:nb
    [~, d] = shortestpathtree(G, i, 'Method', 'positive');
    shortestX(i,:) = d;
end

% --- Step 3: Compute Big-M for each line ---
BigM = zeros(nl, 1);
for l = 1:nl
    from = f(l);
    to   = t(l);
    
    % shortest equivalent reactance between the two buses
    minX = shortestX(from, to);
    
    % estimate max angle diff ≈ max flow * line reactance + shortest path
    % in per-unit: Pf / baseMVA * x
    BigM(l) = (rateA(l)/baseMVA * x(l) + minX) * safety_factor;
end

end