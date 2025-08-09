clc; clear;
define_constants;

%% === 载入 IEEE 24-bus 系统 ===
mpc = loadcase('case24_ieee_rts');

%% === 导出所有发电机原始信息 ===
gen_table = array2table(mpc.gen, ...
    'VariableNames', { ...
        'GEN_BUS','PG','QG','QMAX','QMIN','VG','MBASE', ...
        'GEN_STATUS','PMAX','PMIN','PC1','PC2','QC1MIN', ...
        'QC1MAX','QC2MIN','QC2MAX','RAMP_AGC','RAMP_10', ...
        'RAMP_30','RAMP_Q','APF'});

%% === 保存为CSV文件 ===
writetable(gen_table, 'ieee24_gen_raw.csv');
fprintf('✅ 所有发电机原始信息已导出至 ieee24_gen_raw.csv\n');