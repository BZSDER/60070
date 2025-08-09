function metrics_plot(metrics)
    figure;
    bar([metrics.EENS, metrics.LOLP, metrics.SAIDI, metrics.SAIFI]);
    title('系统可靠性指标');
    ylabel('值');
    set(gca, 'XTickLabel', {'EENS', 'LOLP', 'SAIDI', 'SAIFI'});
    grid on;
end