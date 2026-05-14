function batchSummary = run_batch_pipeline(sceneList, varargin)
% RUN_BATCH_PIPELINE Runs run_pipeline.m for multiple scenes and writes aggregate reports.
% Usage:
%   run_batch_pipeline(["00000325", "00000123"])
%   run_batch_pipeline(["00000325"], 'DatasetName', 'ABC-NEF')

    if nargin < 1 || isempty(sceneList)
        error('sceneList is required.');
    end

    p = inputParser;
    addParameter(p, 'DatasetName', 'ABC-NEF');
    addParameter(p, 'BaseConfigPath', fullfile(pwd, 'config.yaml'));
    addParameter(p, 'ContinueOnError', true);
    parse(p, varargin{:});
    opts = p.Results;

    scenes = string(sceneList);

    if numel(scenes) == 0
        error('sceneList must contain at least one scene.');
    end

    baseCfg = load_base_config(opts.BaseConfigPath);
    outDir = fullfile(pwd, 'tmp', 'batch_runs');
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    batchId = "batch_" + string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    batchDir = fullfile(outDir, batchId);
    mkdir(batchDir);

    results(numel(scenes)) = struct(...
        'scene', "", ...
        'success', false, ...
        'status', "failed", ...
        'total_duration_seconds', NaN, ...
        'filtered_surface_count', 0, ...
        'loft_output_count', 0, ...
        'report_path', "", ...
        'error_message', "");

    for i = 1:numel(scenes)
        scene = scenes(i);
        fprintf('Running scene %s (%d/%d)\n', scene, i, numel(scenes));

        cfg = baseCfg;
        cfg.dataset.name = string(opts.DatasetName);
        cfg.dataset.scene = scene;
        cfg.dataset.curve_graph_file = "auto";
        cfg.dataset.num_views = 0;

        assignin('base', 'RUN_PIPELINE_CFG_OVERRIDE', cfg);

        try
            run_pipeline;
            current = collect_latest_metrics();

            results(i).scene = scene;
            results(i).success = strcmp(string(current.status), "success");
            results(i).status = string(current.status);
            results(i).total_duration_seconds = current.total_duration_seconds;
            results(i).filtered_surface_count = current.filtered_surface_count;
            results(i).loft_output_count = current.loft_output_count;
            results(i).report_path = string(current.report_path);
            results(i).error_message = "";
        catch ME
            results(i).scene = scene;
            results(i).success = false;
            results(i).status = "failed";
            results(i).error_message = string(ME.message);

            if ~opts.ContinueOnError
                evalin('base', 'clear RUN_PIPELINE_CFG_OVERRIDE;');
                rethrow(ME);
            end
        end
    end

    evalin('base', 'clear RUN_PIPELINE_CFG_OVERRIDE;');

    batchSummary = build_batch_summary(string(opts.DatasetName), batchId, results);
    jsonOut = fullfile(batchDir, 'batch_summary.json');
    txtOut = fullfile(batchDir, 'batch_summary.txt');
    csvOut = fullfile(batchDir, 'batch_summary.csv');

    write_json_file(jsonOut, batchSummary);
    write_text_file(txtOut, render_batch_text(batchSummary));
    write_csv_file(csvOut, results);

    fprintf('Batch summary written: %s\n', jsonOut);
end

function cfg = load_base_config(baseConfigPath)
    addpath(fullfile(pwd, 'tools', 'projection'));

    if exist(baseConfigPath, 'file')
        cfg = yaml.loadFile(baseConfigPath);
    else
        cfg = struct();
    end

    if ~isfield(cfg, 'dataset')
        cfg.dataset = struct();
    end
end

function current = collect_latest_metrics()
    reportPath = find_latest_run_report();
    runReport = jsondecode(fileread(reportPath));

    current = struct();
    current.report_path = reportPath;
    current.status = string(runReport.status);
    current.total_duration_seconds = double(runReport.total_duration_seconds);
    current.filtered_surface_count = count_ply_files(fullfile(pwd, 'tmp', 'filtered_surfaces'));
    current.loft_output_count = count_ply_files(fullfile(pwd, 'blender', 'output'));
end

function latestPath = find_latest_run_report()
    d = dir(fullfile(pwd, 'tmp', 'run_logs', 'run_*', 'run_report.json'));
    if isempty(d)
        error('No run reports found under tmp/run_logs.');
    end

    [~, idx] = max([d.datenum]);
    latestPath = fullfile(d(idx).folder, d(idx).name);
end

function n = count_ply_files(folderPath)
    if ~exist(folderPath, 'dir')
        n = 0;
        return;
    end

    d = dir(fullfile(folderPath, '*.ply'));
    n = numel(d);
end

function summary = build_batch_summary(datasetName, batchId, results)
    successMask = [results.success];
    durations = [results.total_duration_seconds];
    validDur = durations(~isnan(durations));

    summary = struct();
    summary.batch_id = batchId;
    summary.dataset = datasetName;
    summary.timestamp = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    summary.total_scenes = numel(results);
    summary.success_count = sum(successMask);
    summary.failure_count = sum(~successMask);

    if isempty(validDur)
        summary.total_duration_seconds = NaN;
        summary.mean_duration_seconds = NaN;
        summary.max_duration_seconds = NaN;
    else
        summary.total_duration_seconds = sum(validDur);
        summary.mean_duration_seconds = mean(validDur);
        summary.max_duration_seconds = max(validDur);
    end

    summary.total_filtered_surfaces = sum([results.filtered_surface_count]);
    summary.total_loft_outputs = sum([results.loft_output_count]);
    summary.results = results;
end

function write_json_file(filePath, s)
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

function write_csv_file(filePath, results)
    fid = fopen(filePath, 'w');
    if fid == -1
        error('Failed to open file for writing: %s', filePath);
    end

    fprintf(fid, 'scene,success,status,total_duration_seconds,filtered_surface_count,loft_output_count,report_path,error_message\n');
    for i = 1:numel(results)
        r = results(i);
        fprintf(fid, '%s,%d,%s,%.6f,%d,%d,%s,%s\n', ...
            sanitize_csv(r.scene), ...
            r.success, ...
            sanitize_csv(r.status), ...
            r.total_duration_seconds, ...
            r.filtered_surface_count, ...
            r.loft_output_count, ...
            sanitize_csv(r.report_path), ...
            sanitize_csv(r.error_message));
    end

    fclose(fid);
end

function textBody = render_batch_text(summary)
    lines = strings(0, 1);
    lines(end + 1) = "Batch ID: " + summary.batch_id;
    lines(end + 1) = "Dataset: " + summary.dataset;
    lines(end + 1) = "Timestamp: " + summary.timestamp;
    lines(end + 1) = "Total scenes: " + string(summary.total_scenes);
    lines(end + 1) = "Success: " + string(summary.success_count);
    lines(end + 1) = "Failure: " + string(summary.failure_count);
    lines(end + 1) = "Total runtime(sec): " + string(summary.total_duration_seconds);
    lines(end + 1) = "Mean runtime(sec): " + string(summary.mean_duration_seconds);
    lines(end + 1) = "Max runtime(sec): " + string(summary.max_duration_seconds);
    lines(end + 1) = "Total filtered surfaces: " + string(summary.total_filtered_surfaces);
    lines(end + 1) = "Total loft outputs: " + string(summary.total_loft_outputs);

    textBody = strjoin(cellstr(lines), newline);
end

function out = sanitize_csv(v)
    s = string(v);
    s = replace(s, '"', '""');
    out = '"' + s + '"';
end
