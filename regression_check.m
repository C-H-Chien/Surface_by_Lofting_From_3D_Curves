function report = regression_check(varargin)
% REGRESSION_CHECK Runs pipeline regression validation and writes a report.
% Usage:
%   regression_check()
%   regression_check('Mode', 'create-baseline')
%   regression_check('RunPipeline', false, 'BaselineFile', 'tmp/baseline_metrics.json')

    p = inputParser;
    addParameter(p, 'Mode', 'check'); % 'check' | 'create-baseline'
    addParameter(p, 'RunPipeline', true);
    addParameter(p, 'BaselineFile', fullfile(pwd, 'tmp', 'baseline_metrics.json'));
    addParameter(p, 'MaxRuntimeRatio', 1.25);
    addParameter(p, 'MinFilteredSurfaceRatio', 0.90);
    addParameter(p, 'MinLoftOutputRatio', 0.90);
    parse(p, varargin{:});

    opts = p.Results;
    mode = string(opts.Mode);

    if opts.RunPipeline
        run_pipeline;
    end

    current = collect_current_metrics();
    outDir = fullfile(pwd, 'tmp', 'regression');
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    timestamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    jsonOut = fullfile(outDir, "regression_report_" + timestamp + ".json");
    txtOut = fullfile(outDir, "regression_report_" + timestamp + ".txt");

    if mode == "create-baseline"
        write_json_file(opts.BaselineFile, current);

        report = struct();
        report.mode = 'create-baseline';
        report.passed = true;
        report.current = current;
        report.baseline_file = string(opts.BaselineFile);
        report.message = "Baseline created.";

        write_json_file(jsonOut, report);
        write_text_file(txtOut, render_summary(report));
        fprintf('Baseline written: %s\n', opts.BaselineFile);
        fprintf('Regression report: %s\n', jsonOut);
        return;
    end

    if ~exist(opts.BaselineFile, 'file')
        error('Baseline file not found: %s. Run regression_check(''Mode'',''create-baseline'') first.', opts.BaselineFile);
    end

    baseline = jsondecode(fileread(opts.BaselineFile));
    checks = evaluate_checks(current, baseline, opts);

    report = struct();
    report.mode = 'check';
    report.timestamp = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    report.passed = all([checks.status_ok, checks.filtered_ok, checks.loft_ok, checks.runtime_ok]);
    report.current = current;
    report.baseline = baseline;
    report.thresholds = struct(...
        'max_runtime_ratio', opts.MaxRuntimeRatio, ...
        'min_filtered_surface_ratio', opts.MinFilteredSurfaceRatio, ...
        'min_loft_output_ratio', opts.MinLoftOutputRatio);
    report.checks = checks;

    write_json_file(jsonOut, report);
    write_text_file(txtOut, render_summary(report));

    fprintf('Regression report: %s\n', jsonOut);
    fprintf('Regression summary: %s\n', txtOut);

    if ~report.passed
        error('Regression check failed. See report: %s', jsonOut);
    end
end

function checks = evaluate_checks(current, baseline, opts)
    checks = struct();

    checks.status_ok = strcmp(string(current.status), "success");

    if baseline.filtered_surface_count <= 0
        checks.filtered_ratio = Inf;
        checks.filtered_ok = current.filtered_surface_count > 0;
    else
        checks.filtered_ratio = current.filtered_surface_count / baseline.filtered_surface_count;
        checks.filtered_ok = checks.filtered_ratio >= opts.MinFilteredSurfaceRatio;
    end

    if baseline.loft_output_count <= 0
        checks.loft_ratio = Inf;
        checks.loft_ok = current.loft_output_count > 0;
    else
        checks.loft_ratio = current.loft_output_count / baseline.loft_output_count;
        checks.loft_ok = checks.loft_ratio >= opts.MinLoftOutputRatio;
    end

    if baseline.total_duration_seconds <= 0
        checks.runtime_ratio = 0;
        checks.runtime_ok = true;
    else
        checks.runtime_ratio = current.total_duration_seconds / baseline.total_duration_seconds;
        checks.runtime_ok = checks.runtime_ratio <= opts.MaxRuntimeRatio;
    end
end

function metrics = collect_current_metrics()
    reportPath = find_latest_run_report();
    runReport = jsondecode(fileread(reportPath));

    filteredDir = fullfile(pwd, 'tmp', 'filtered_surfaces');
    loftOutDir = fullfile(pwd, 'blender', 'output');

    metrics = struct();
    metrics.report_path = string(reportPath);
    metrics.run_id = string(runReport.run_id);
    metrics.status = string(runReport.status);
    metrics.dataset = string(runReport.dataset);
    metrics.scene = string(runReport.scene);
    metrics.total_duration_seconds = double(runReport.total_duration_seconds);
    metrics.filtered_surface_count = count_ply_files(filteredDir);
    metrics.loft_output_count = count_ply_files(loftOutDir);
end

function n = count_ply_files(folderPath)
    if ~exist(folderPath, 'dir')
        n = 0;
        return;
    end

    d = dir(fullfile(folderPath, '*.ply'));
    n = numel(d);
end

function latestPath = find_latest_run_report()
    logRoot = fullfile(pwd, 'tmp', 'run_logs');
    if ~exist(logRoot, 'dir')
        error('No run logs found at %s. Run pipeline first.', logRoot);
    end

    d = dir(fullfile(logRoot, 'run_*', 'run_report.json'));
    if isempty(d)
        error('No run_report.json found under %s.', logRoot);
    end

    [~, idx] = max([d.datenum]);
    latestPath = fullfile(d(idx).folder, d(idx).name);
end

function write_json_file(filePath, s)
    outDir = fileparts(filePath);
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    fid = fopen(filePath, 'w');
    if fid == -1
        error('Failed to open file for writing: %s', filePath);
    end

    fprintf(fid, '%s', jsonencode(s, 'PrettyPrint', true));
    fclose(fid);
end

function write_text_file(filePath, textBody)
    fid = fopen(filePath, 'w');
    if fid == -1
        error('Failed to open file for writing: %s', filePath);
    end

    fprintf(fid, '%s\n', textBody);
    fclose(fid);
end

function body = render_summary(report)
    lines = strings(0, 1);
    lines(end + 1) = "Regression Mode: " + string(report.mode);
    lines(end + 1) = "Timestamp: " + string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    if isfield(report, 'passed')
        lines(end + 1) = "Passed: " + string(report.passed);
    end

    if isfield(report, 'current')
        c = report.current;
        lines(end + 1) = "Current Dataset/Scene: " + c.dataset + "/" + c.scene;
        lines(end + 1) = "Current Status: " + c.status;
        lines(end + 1) = "Current Runtime(sec): " + string(c.total_duration_seconds);
        lines(end + 1) = "Current Filtered Surfaces: " + string(c.filtered_surface_count);
        lines(end + 1) = "Current Loft Outputs: " + string(c.loft_output_count);
    end

    if isfield(report, 'checks')
        ck = report.checks;
        lines(end + 1) = "status_ok: " + string(ck.status_ok);
        lines(end + 1) = "filtered_ok: " + string(ck.filtered_ok) + " (ratio=" + string(ck.filtered_ratio) + ")";
        lines(end + 1) = "loft_ok: " + string(ck.loft_ok) + " (ratio=" + string(ck.loft_ratio) + ")";
        lines(end + 1) = "runtime_ok: " + string(ck.runtime_ok) + " (ratio=" + string(ck.runtime_ratio) + ")";
    end

    body = strjoin(cellstr(lines), newline);
end
