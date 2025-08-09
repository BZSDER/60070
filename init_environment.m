function init_environment()
    %% Gurobi path
    gurobi_matlab_path = 'G:\SCHDOCS\60070\matlab_code\gurobi\win64\matlab';
    if exist(fullfile(gurobi_matlab_path, 'gurobi_setup.m'), 'file')
        addpath(gurobi_matlab_path);
        run(fullfile(gurobi_matlab_path, 'gurobi_setup.m'));
        fprintf('✅ Gurobi initialised\n');
    else
        error('Gurobi 路径错误：%s', gurobi_matlab_path);
    end

    %% YALMIP path
    yalmip_path = 'G:\SCHDOCS\60070\matlab_code\YALMIP-master';
    if exist(yalmip_path, 'dir')
        addpath(genpath(yalmip_path));
        fprintf('✅ YALMIP initialised\n');
    else
        warning('⚠️ 找不到 YALMIP 路径：%s', yalmip_path);
    end

    %% solver setting
    ops = sdpsettings('solver', 'gurobi', 'verbose', 1);
    assignin('base', 'ops', ops);

    %% MATPOWER path
    matpower_path = 'G:\SCHDOCS\60070\matlab_code\matpower8.0\lib';
    if exist(fullfile(matpower_path, 'runpf.m'), 'file')
        addpath(genpath(matpower_path));
        fprintf('✅ MATPOWER 路径添加成功\n');
    else
        warning('⚠️ 找不到 MATPOWER 路径：%s', matpower_path);
    end
end