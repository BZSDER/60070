function scenarios = scenario_library()
% 定义环境场景及其对支路/机组可靠性的影响

% 每个场景定义:
%   lambda_factor_branch : 支路失效率放大系数
%   lambda_factor_gen    : 发电机失效率放大系数
%   load_factor          : 负荷放大系数

scenarios.normal = struct( ...
    'lambda_factor_branch', 1.0, ...
    'lambda_factor_gen',    1.0, ...
    'load_factor',          1.0 );

scenarios.cold = struct( ...
    'lambda_factor_branch', 1.5, ...  % 低温支路更容易断
    'lambda_factor_gen',    1.2, ...  % 发电机稍易故障
    'load_factor',          1.05 );

scenarios.hot = struct( ...
    'lambda_factor_branch', 1.2, ...  % 高温线路老化
    'lambda_factor_gen',    1.3, ...  % 高温机组受限
    'load_factor',          1.1 );

scenarios.storm = struct( ...
    'lambda_factor_branch', 2.5, ...  % 风暴支路极易断开
    'lambda_factor_gen',    2.0, ...  % 风暴机组受损
    'load_factor',          1.0 );    % 负荷不变
end
